#import "OrenAVMKit.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <dispatch/dispatch.h>
#import <limits.h>
#import <zlib.h>

static BOOL OrenAVMPackageAssignError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OBC package error"}];
    }
    return NO;
}

static NSString* OrenAVMPackageString(NSDictionary<NSString*, id>* manifest, NSString* key) {
    id v = manifest[key];
    return [v isKindOfClass:[NSString class]] ? (NSString*)v : nil;
}

static NSNumber* OrenAVMPackageNumber(NSDictionary<NSString*, id>* manifest, NSString* key) {
    id v = manifest[key];
    return [v isKindOfClass:[NSNumber class]] ? (NSNumber*)v : nil;
}

static NSData* OrenAVMPackageDecodeHex(NSString* hex) {
    if ((hex.length & 1u) != 0) return nil;
    NSMutableData* out = [NSMutableData dataWithLength:hex.length / 2u];
    uint8_t* bytes = out.mutableBytes;
    for (NSUInteger i = 0; i < hex.length; i += 2u) {
        unsigned int v = 0;
        NSString* part = [hex substringWithRange:NSMakeRange(i, 2u)];
        NSScanner* scanner = [NSScanner scannerWithString:part];
        if (![scanner scanHexInt:&v] || !scanner.isAtEnd || v > 255u) return nil;
        bytes[i / 2u] = (uint8_t)v;
    }
    return out;
}

static NSData* OrenAVMPackageDecodeP256PublicKey(NSString* b64) {
    if (![b64 isKindOfClass:[NSString class]] || b64.length == 0) return nil;
    NSData* data = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    const uint8_t* bytes = data.bytes;
    if (data.length != 65u || bytes[0] != 4u) return nil;
    return data;
}

static NSString* OrenAVMPackageCanonicalURLOrigin(NSURL* url) {
    NSString* scheme = url.scheme.lowercaseString;
    NSString* host = url.host.lowercaseString;
    if (scheme.length == 0 || host.length == 0) return nil;
    NSNumber* port = url.port;
    BOOL defaultPort = (!port ||
        (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"ws"]) && port.unsignedIntValue == 80u) ||
        (([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"wss"]) && port.unsignedIntValue == 443u));
    NSString* displayHost = [host containsString:@":"] ? [NSString stringWithFormat:@"[%@]", host] : host;
    if (defaultPort) return [NSString stringWithFormat:@"%@://%@", scheme, displayHost];
    return [NSString stringWithFormat:@"%@://%@:%@", scheme, displayHost, port];
}

static BOOL OrenAVMPackageURLAllowedByHostOrOrigin(NSURL* url, NSSet<NSString*>* allowedHosts) {
    if (allowedHosts.count == 0) return YES;
    NSString* host = url.host.lowercaseString;
    NSString* origin = OrenAVMPackageCanonicalURLOrigin(url);
    if (host.length == 0 || origin.length == 0) return NO;
    for (NSString* entry in allowedHosts) {
        if (![entry isKindOfClass:[NSString class]] || entry.length == 0) continue;
        NSURL* entryURL = [entry containsString:@"://"] ? [NSURL URLWithString:entry] : nil;
        if (entryURL) {
            NSString* entryOrigin = OrenAVMPackageCanonicalURLOrigin(entryURL);
            if ([origin isEqualToString:entryOrigin]) return YES;
        } else if ([host isEqualToString:entry.lowercaseString]) {
            return YES;
        }
    }
    return NO;
}

static BOOL OrenAVMPackageVerifyP256Signature(NSData* publicKeyX963, NSData* message, NSData* signatureDER) {
    if (publicKeyX963.length != 65u || signatureDER.length == 0 || message.length == 0) return NO;
    NSDictionary* attrs = @{
        (__bridge NSString*)kSecAttrKeyType: (__bridge NSString*)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge NSString*)kSecAttrKeyClass: (__bridge NSString*)kSecAttrKeyClassPublic,
        (__bridge NSString*)kSecAttrKeySizeInBits: @256,
    };
    CFErrorRef cfError = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)publicKeyX963, (__bridge CFDictionaryRef)attrs, &cfError);
    if (!key) {
        if (cfError) CFRelease(cfError);
        return NO;
    }
    BOOL ok = SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeVerify, kSecKeyAlgorithmECDSASignatureMessageX962SHA256) &&
        SecKeyVerifySignature(key,
                              kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                              (__bridge CFDataRef)message,
                              (__bridge CFDataRef)signatureDER,
                              &cfError);
    if (cfError) CFRelease(cfError);
    CFRelease(key);
    return ok;
}

@interface OrenAVMOBCTrustBundle ()

- (instancetype)initWithStorePublicKeys:(NSDictionary<NSString*, NSData*>*)storePublicKeys
                    publisherPublicKeys:(NSDictionary<NSString*, NSData*>*)publisherPublicKeys
                      defaultStoreKeyID:(NSString*)defaultStoreKeyID
                  defaultStorePublicKey:(NSData*)defaultStorePublicKey NS_DESIGNATED_INITIALIZER;

@end

@implementation OrenAVMOBCTrustBundle

- (instancetype)initWithStorePublicKeys:(NSDictionary<NSString*, NSData*>*)storePublicKeys
                    publisherPublicKeys:(NSDictionary<NSString*, NSData*>*)publisherPublicKeys
                      defaultStoreKeyID:(NSString*)defaultStoreKeyID
                  defaultStorePublicKey:(NSData*)defaultStorePublicKey {
    self = [super init];
    if (self) {
        _storePublicKeys = [storePublicKeys copy];
        _publisherPublicKeys = [publisherPublicKeys copy];
        _defaultStoreKeyID = [defaultStoreKeyID copy];
        _defaultStorePublicKey = [defaultStorePublicKey copy];
    }
    return self;
}

- (instancetype)init {
    return [self initWithStorePublicKeys:@{}
                     publisherPublicKeys:@{}
                       defaultStoreKeyID:@""
                   defaultStorePublicKey:[NSData data]];
}

+ (instancetype)loadTrustBundleAtURL:(NSURL*)url error:(NSError**)error {
    if (!url.isFileURL) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle URL must be a file URL");
        return nil;
    }
    NSData* data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle must be a JSON object");
        return nil;
    }
    NSDictionary<NSString*, id>* bundle = (NSDictionary<NSString*, id>*)json;
    if (![OrenAVMPackageString(bundle, @"schema") isEqualToString:@"oren.obc.trust.v0"]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle schema is unsupported");
        return nil;
    }
    id storeKeysRaw = bundle[@"store_keys"];
    if (![storeKeysRaw isKindOfClass:[NSArray class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle store_keys must be an array");
        return nil;
    }
    NSMutableDictionary<NSString*, NSData*>* storeKeys = [NSMutableDictionary dictionary];
    NSString* defaultStoreKeyID = nil;
    NSData* defaultStorePublicKey = nil;
    for (id entryRaw in (NSArray*)storeKeysRaw) {
        if (![entryRaw isKindOfClass:[NSDictionary class]]) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle store key entries must be objects");
            return nil;
        }
        NSDictionary<NSString*, id>* entry = (NSDictionary<NSString*, id>*)entryRaw;
        NSString* keyID = OrenAVMPackageString(entry, @"id");
        NSString* alg = OrenAVMPackageString(entry, @"alg");
        NSData* publicKey = OrenAVMPackageDecodeP256PublicKey(OrenAVMPackageString(entry, @"public_key_x963_b64"));
        if (keyID.length == 0 || ![alg isEqualToString:@"p256-sha256-der"] || !publicKey) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle store key entry is invalid");
            return nil;
        }
        storeKeys[keyID] = publicKey;
        if (!defaultStoreKeyID) {
            defaultStoreKeyID = keyID;
            defaultStorePublicKey = publicKey;
        }
    }
    if (!defaultStoreKeyID || !defaultStorePublicKey) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle must include at least one store key");
        return nil;
    }
    id publisherKeysRaw = bundle[@"publisher_keys"];
    if (![publisherKeysRaw isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle publisher_keys must be an object");
        return nil;
    }
    NSMutableDictionary<NSString*, NSData*>* publisherKeys = [NSMutableDictionary dictionary];
    for (NSString* publisherID in (NSDictionary*)publisherKeysRaw) {
        id entryRaw = ((NSDictionary*)publisherKeysRaw)[publisherID];
        if (![publisherID isKindOfClass:[NSString class]] || publisherID.length == 0 ||
            ![entryRaw isKindOfClass:[NSDictionary class]]) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle publisher key entry is invalid");
            return nil;
        }
        NSDictionary<NSString*, id>* entry = (NSDictionary<NSString*, id>*)entryRaw;
        NSString* alg = OrenAVMPackageString(entry, @"alg");
        NSData* publicKey = OrenAVMPackageDecodeP256PublicKey(OrenAVMPackageString(entry, @"public_key_x963_b64"));
        if (![alg isEqualToString:@"p256-sha256-der"] || !publicKey) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle publisher key entry is invalid");
            return nil;
        }
        publisherKeys[publisherID] = publicKey;
    }
    return [[OrenAVMOBCTrustBundle alloc] initWithStorePublicKeys:storeKeys
                                             publisherPublicKeys:publisherKeys
                                               defaultStoreKeyID:defaultStoreKeyID
                                           defaultStorePublicKey:defaultStorePublicKey];
}

@end

static BOOL OrenAVMPackagePathIsSafe(NSString* path) {
    if (path.length == 0 || [path hasPrefix:@"/"] || [path containsString:@"\0"]) return NO;
    for (NSString* part in [path pathComponents]) {
        if ([part isEqualToString:@".."]) return NO;
    }
    return YES;
}

static NSURL* OrenAVMPackageAppendSafeRelativePath(NSURL* root, NSString* path, BOOL isDirectory) {
    if (!root.isFileURL || !OrenAVMPackagePathIsSafe(path)) return nil;
    NSURL* out = root;
    NSArray<NSString*>* parts = [path pathComponents];
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSString* part = parts[i];
        if (part.length == 0 || [part isEqualToString:@"."]) continue;
        BOOL last = i + 1u == parts.count;
        out = [out URLByAppendingPathComponent:part isDirectory:(last ? isDirectory : YES)];
    }
    return out;
}

static NSURL* OrenAVMPackageResolveStoreURL(NSURL* baseURL, NSString* path) {
    if (path.length == 0) return nil;
    NSURL* url = [NSURL URLWithString:path];
    if (url.scheme.length > 0) return url;
    if (!OrenAVMPackagePathIsSafe(path)) return nil;
    return [[NSURL URLWithString:path relativeToURL:baseURL] absoluteURL];
}

static uint16_t OrenAVMPackageReadLE16(const uint8_t* bytes, NSUInteger length, NSUInteger off) {
    if (off + 2u > length) return 0;
    return (uint16_t)bytes[off] | ((uint16_t)bytes[off + 1u] << 8);
}

static uint32_t OrenAVMPackageReadLE32(const uint8_t* bytes, NSUInteger length, NSUInteger off) {
    if (off + 4u > length) return 0;
    return (uint32_t)bytes[off] |
        ((uint32_t)bytes[off + 1u] << 8) |
        ((uint32_t)bytes[off + 2u] << 16) |
        ((uint32_t)bytes[off + 3u] << 24);
}

static NSData* OrenAVMPackageInflateRawDeflate(const uint8_t* input, NSUInteger inputLen, NSUInteger outputLen) {
    NSMutableData* out = [NSMutableData dataWithLength:outputLen];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef*)input;
    stream.avail_in = (uInt)inputLen;
    stream.next_out = out.mutableBytes;
    stream.avail_out = (uInt)outputLen;
    if (inputLen > UINT_MAX || outputLen > UINT_MAX || inflateInit2(&stream, -MAX_WBITS) != Z_OK) return nil;
    int rc = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);
    if (rc != Z_STREAM_END || stream.total_out != outputLen) return nil;
    return out;
}

static BOOL OrenAVMPackageWriteZIPEntry(NSData* zipData,
                                        NSUInteger localHeaderOffset,
                                        NSString* name,
                                        uint16_t method,
                                        uint32_t expectedCRC,
                                        uint32_t compressedSize,
                                        uint32_t uncompressedSize,
                                        NSURL* destinationRoot,
                                        NSError** error) {
    const uint8_t* bytes = zipData.bytes;
    NSUInteger length = zipData.length;
    if (localHeaderOffset + 30u > length || OrenAVMPackageReadLE32(bytes, length, localHeaderOffset) != 0x04034b50u) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle has invalid local ZIP header");
    }
    uint16_t nameLen = OrenAVMPackageReadLE16(bytes, length, localHeaderOffset + 26u);
    uint16_t extraLen = OrenAVMPackageReadLE16(bytes, length, localHeaderOffset + 28u);
    NSUInteger dataOffset = localHeaderOffset + 30u + nameLen + extraLen;
    if (dataOffset > length || compressedSize > length - dataOffset) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle entry is truncated");
    }
    NSData* body = nil;
    const uint8_t* compressed = bytes + dataOffset;
    if (method == 0) {
        if (compressedSize != uncompressedSize) {
            return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle stored entry size mismatch");
        }
        body = [NSData dataWithBytesNoCopy:(void*)compressed length:uncompressedSize freeWhenDone:NO];
    } else if (method == 8) {
        body = OrenAVMPackageInflateRawDeflate(compressed, compressedSize, uncompressedSize);
        if (!body) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle deflate entry failed");
    } else {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle uses unsupported compression");
    }
    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, body.bytes, (uInt)body.length);
    if ((uint32_t)crc != expectedCRC) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle entry CRC mismatch");
    }
    NSURL* outURL = OrenAVMPackageAppendSafeRelativePath(destinationRoot, name, NO);
    if (!outURL) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle path is unsafe");
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtURL:[outURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return [body writeToURL:outURL options:NSDataWritingAtomic error:error];
}

static BOOL OrenAVMPackageExtractReleaseBundle(NSData* zipData, NSURL* destinationRoot, NSError** error) {
    if (!destinationRoot.isFileURL || zipData.length < 22u) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle is invalid");
    }
    const uint8_t* bytes = zipData.bytes;
    NSUInteger length = zipData.length;
    NSUInteger minEOCD = length > 65557u ? length - 65557u : 0u;
    NSUInteger eocd = NSNotFound;
    for (NSUInteger off = length - 22u;; off--) {
        if (OrenAVMPackageReadLE32(bytes, length, off) == 0x06054b50u) {
            eocd = off;
            break;
        }
        if (off == minEOCD) break;
    }
    if (eocd == NSNotFound) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle missing ZIP directory");
    uint16_t entries = OrenAVMPackageReadLE16(bytes, length, eocd + 10u);
    uint32_t centralSize = OrenAVMPackageReadLE32(bytes, length, eocd + 12u);
    uint32_t centralOffset = OrenAVMPackageReadLE32(bytes, length, eocd + 16u);
    if (centralOffset > length || centralSize > length - centralOffset) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle ZIP directory is truncated");
    }
    BOOL sawManifest = NO;
    BOOL sawProgram = NO;
    NSUInteger off = centralOffset;
    for (uint16_t i = 0; i < entries; i++) {
        if (off + 46u > length || OrenAVMPackageReadLE32(bytes, length, off) != 0x02014b50u) {
            return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle has invalid ZIP directory entry");
        }
        uint16_t flags = OrenAVMPackageReadLE16(bytes, length, off + 8u);
        uint16_t method = OrenAVMPackageReadLE16(bytes, length, off + 10u);
        uint32_t crc = OrenAVMPackageReadLE32(bytes, length, off + 16u);
        uint32_t compressedSize = OrenAVMPackageReadLE32(bytes, length, off + 20u);
        uint32_t uncompressedSize = OrenAVMPackageReadLE32(bytes, length, off + 24u);
        uint16_t nameLen = OrenAVMPackageReadLE16(bytes, length, off + 28u);
        uint16_t extraLen = OrenAVMPackageReadLE16(bytes, length, off + 30u);
        uint16_t commentLen = OrenAVMPackageReadLE16(bytes, length, off + 32u);
        uint32_t externalAttrs = OrenAVMPackageReadLE32(bytes, length, off + 38u);
        uint32_t localHeaderOffset = OrenAVMPackageReadLE32(bytes, length, off + 42u);
        NSUInteger nameOff = off + 46u;
        NSUInteger next = nameOff + nameLen + extraLen + commentLen;
        if (next > length || (flags & 1u) != 0 || compressedSize > 512u * 1024u * 1024u || uncompressedSize > 512u * 1024u * 1024u) {
            return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle entry is unsupported");
        }
        NSString* name = [[NSString alloc] initWithBytes:bytes + nameOff length:nameLen encoding:NSUTF8StringEncoding];
        if (name.length == 0) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle entry path is invalid");
        BOOL isDirectory = [name hasSuffix:@"/"];
        NSString* cleanName = isDirectory ? [name substringToIndex:name.length - 1u] : name;
        if (!OrenAVMPackagePathIsSafe(cleanName) || (externalAttrs & 0xA0000000u) == 0xA0000000u) {
            return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle entry path is unsafe");
        }
        if (isDirectory) {
            NSURL* dirURL = OrenAVMPackageAppendSafeRelativePath(destinationRoot, cleanName, YES);
            if (!dirURL || ![[NSFileManager defaultManager] createDirectoryAtURL:dirURL withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        } else {
            if ([name isEqualToString:@"package.json"]) sawManifest = YES;
            if ([name isEqualToString:@"program.obc"]) sawProgram = YES;
            if (!OrenAVMPackageWriteZIPEntry(zipData, localHeaderOffset, name, method, crc, compressedSize, uncompressedSize, destinationRoot, error)) return NO;
        }
        off = next;
    }
    if (!sawManifest || !sawProgram) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle must contain package.json and program.obc");
    }
    return YES;
}

static uint64_t OrenAVMPackageDomainForCapability(NSString* cap) {
    NSString* c = cap.uppercaseString;
    if ([c isEqualToString:@"CORE"]) return OrenAVMDomainCore;
    if ([c isEqualToString:@"FS"] || [c isEqualToString:@"VFS"]) return OrenAVMDomainFS;
    if ([c isEqualToString:@"TIME"]) return OrenAVMDomainTime;
    if ([c isEqualToString:@"NET"] || [c isEqualToString:@"VNET"]) return OrenAVMDomainNet;
    if ([c isEqualToString:@"PROC"] || [c isEqualToString:@"VPROC"]) return OrenAVMDomainProc;
    if ([c isEqualToString:@"EXIT"]) return OrenAVMDomainExit;
    if ([c isEqualToString:@"GFX"] || [c isEqualToString:@"INPUT"] || [c isEqualToString:@"UI"]) return OrenAVMDomainGFX;
    if ([c isEqualToString:@"PERMISSION"]) return OrenAVMDomainPermission;
    return 0;
}

static BOOL OrenAVMPackageFetchURLData(NSURL* url,
                                       NSSet<NSString*>* allowedHosts,
                                       NSTimeInterval timeoutSeconds,
                                       NSData** outData,
                                       NSError** error) {
    NSString* scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"network fetch requires an http or https URL");
    }
    NSString* host = url.host;
    if (host.length == 0) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"network fetch URL must include a host");
    if (!OrenAVMPackageURLAllowedByHostOrOrigin(url, allowedHosts)) {
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_VM, @"network fetch URL is not allowlisted");
    }
    NSTimeInterval effectiveTimeout = timeoutSeconds > 0.0 ? timeoutSeconds : 15.0;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:effectiveTimeout];
    request.HTTPMethod = @"GET";
    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfig.timeoutIntervalForRequest = effectiveTimeout;
    sessionConfig.timeoutIntervalForResource = effectiveTimeout;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:sessionConfig];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData* responseData = nil;
    __block NSURLResponse* response = nil;
    __block NSError* requestError = nil;
    NSURLSessionDataTask* task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData* data, NSURLResponse* taskResponse, NSError* taskError) {
        responseData = data ? [data copy] : [NSData data];
        response = taskResponse;
        requestError = taskError;
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    int64_t timeoutNanos = (int64_t)(effectiveTimeout * (NSTimeInterval)NSEC_PER_SEC);
    if (timeoutNanos <= 0) timeoutNanos = (int64_t)(15.0 * (NSTimeInterval)NSEC_PER_SEC);
    long waitResult = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, timeoutNanos));
    if (waitResult != 0) {
        [task cancel];
        [session finishTasksAndInvalidate];
        return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_VM, @"network fetch timed out");
    }
    [session finishTasksAndInvalidate];
    if (requestError) {
        if (error) *error = requestError;
        return NO;
    }
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = ((NSHTTPURLResponse*)response).statusCode;
        if (statusCode < 200 || statusCode >= 300) {
            NSString* message = [NSString stringWithFormat:@"network fetch returned HTTP %ld", (long)statusCode];
            return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_VM, message);
        }
    }
    if (outData) *outData = responseData ?: [NSData data];
    return YES;
}

static NSURL* OrenAVMPackageUpdateURL(NSURL* storeBaseURL, NSString* publisher, NSString* name, NSString* currentVersion) {
    if (!storeBaseURL || publisher.length == 0 || name.length == 0) return nil;
    NSURLComponents* components = [NSURLComponents componentsWithURL:storeBaseURL resolvingAgainstBaseURL:NO];
    if (!components) return nil;
    NSString* indexPath = @"/api/v0/index.json";
    NSString* root = components.path ?: @"";
    if ([root hasSuffix:indexPath]) {
        root = [root substringToIndex:root.length - indexPath.length];
    }
    root = [root stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSString* route = [NSString stringWithFormat:@"api/v0/packages/%@/%@/update", publisher, name];
    components.path = root.length > 0 ? [NSString stringWithFormat:@"/%@/%@", root, route] : [@"/" stringByAppendingString:route];
    if (currentVersion.length > 0) {
        NSURLQueryItem* item = [NSURLQueryItem queryItemWithName:@"current_version" value:currentVersion];
        components.queryItems = @[item];
    } else {
        components.queryItems = @[];
    }
    return components.URL;
}

static NSURL* OrenAVMPackageInstallMetadataURL(NSURL* packageRoot) {
    return packageRoot.isFileURL ? [packageRoot URLByAppendingPathComponent:@".oren-install.json" isDirectory:NO] : nil;
}

static int64_t OrenAVMPackageUnixMillis(void) {
    return (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static NSDictionary* OrenAVMPackageReadInstallMetadata(NSURL* packageRoot, NSError** error) {
    NSURL* metaURL = OrenAVMPackageInstallMetadataURL(packageRoot);
    if (!metaURL) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package install metadata path is invalid");
        return nil;
    }
    NSData* data = [NSData dataWithContentsOfURL:metaURL options:0 error:error];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package install metadata must be a JSON object");
        return nil;
    }
    NSDictionary* metadata = (NSDictionary*)json;
    NSString* schema = OrenAVMPackageString(metadata, @"schema");
    if (![schema isEqualToString:@"oren.obc.package.install.v0"]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package install metadata is invalid");
        return nil;
    }
    return metadata;
}

static BOOL OrenAVMPackageWriteInstallMetadata(NSURL* packageRoot,
                                               NSURL* indexURL,
                                               NSDictionary* manifest,
                                               NSError** error) {
    NSURL* outURL = OrenAVMPackageInstallMetadataURL(packageRoot);
    if (!outURL || !indexURL) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package install metadata path is invalid");
    NSString* publisher = OrenAVMPackageString(manifest, @"publisher") ?: @"";
    NSString* name = OrenAVMPackageString(manifest, @"name") ?: @"";
    NSString* version = OrenAVMPackageString(manifest, @"version") ?: @"";
    NSDictionary<NSString*, id>* metadata = @{
        @"schema": @"oren.obc.package.install.v0",
        @"package_id": [NSString stringWithFormat:@"%@/%@/%@", publisher, name, version],
        @"publisher": publisher,
        @"name": name,
        @"version": version,
        @"store_index_url": indexURL.absoluteString ?: @"",
        @"installed_at_unix_ms": @(OrenAVMPackageUnixMillis())
    };
    NSData* data = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    return [data writeToURL:outURL options:NSDataWritingAtomic error:error];
}

static NSURL* OrenAVMPackageReadInstallIndexURL(NSURL* packageRoot, NSError** error) {
    NSDictionary* metadata = OrenAVMPackageReadInstallMetadata(packageRoot, error);
    if (!metadata) return nil;
    NSString* url = OrenAVMPackageString(metadata, @"store_index_url");
    if (url.length == 0) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package install metadata URL is missing");
        return nil;
    }
    NSURL* indexURL = [NSURL URLWithString:url];
    if (!indexURL) OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package install metadata URL is invalid");
    return indexURL;
}

static NSSet<NSString*>* OrenAVMPackageEffectiveAllowedHosts(NSSet<NSString*>* allowedHosts, NSURL* url) {
    if (allowedHosts.count > 0 || url.host.length == 0) return allowedHosts;
    return [NSSet setWithObject:url.host];
}

@interface OrenAVMPackage ()
- (instancetype)initWithDirectoryURL:(NSURL*)directoryURL
                            manifest:(NSDictionary<NSString*, id>*)manifest
                             obcData:(NSData*)obcData
                           packageID:(NSString*)packageID
                                name:(NSString*)name
                           publisher:(NSString*)publisher
                             version:(NSString*)version
                        capabilities:(NSArray<NSString*>*)capabilities;
@end

@implementation OrenAVMPackage

- (instancetype)initWithDirectoryURL:(NSURL*)directoryURL
                            manifest:(NSDictionary<NSString*, id>*)manifest
                             obcData:(NSData*)obcData
                           packageID:(NSString*)packageID
                                name:(NSString*)name
                           publisher:(NSString*)publisher
                             version:(NSString*)version
                        capabilities:(NSArray<NSString*>*)capabilities {
    self = [super init];
    if (!self) return nil;
    _directoryURL = [directoryURL copy];
    _manifest = [manifest copy];
    _obcData = [obcData copy];
    _packageID = [packageID copy];
    _name = [name copy];
    _publisher = [publisher copy];
    _version = [version copy];
    _capabilities = [capabilities copy];
    return self;
}

@end

@interface OrenAVMPackageUpdateStatus ()
- (instancetype)initWithPublisher:(NSString*)publisher
                              name:(NSString*)name
                    currentVersion:(NSString*)currentVersion
                     latestVersion:(NSString*)latestVersion
                   updateAvailable:(BOOL)updateAvailable
                     latestRelease:(NSDictionary<NSString*, id>*)latestRelease
                checkedAtUnixMillis:(int64_t)checkedAtUnixMillis;
@end

@implementation OrenAVMPackageUpdateStatus

- (instancetype)initWithPublisher:(NSString*)publisher
                              name:(NSString*)name
                    currentVersion:(NSString*)currentVersion
                     latestVersion:(NSString*)latestVersion
                   updateAvailable:(BOOL)updateAvailable
                     latestRelease:(NSDictionary<NSString*, id>*)latestRelease
                checkedAtUnixMillis:(int64_t)checkedAtUnixMillis {
    self = [super init];
    if (!self) return nil;
    _publisher = [publisher copy];
    _name = [name copy];
    _currentVersion = [currentVersion copy];
    _latestVersion = [latestVersion copy];
    _updateAvailable = updateAvailable;
    _latestRelease = [latestRelease copy];
    _checkedAtUnixMillis = checkedAtUnixMillis;
    return self;
}

- (instancetype)init {
    return [self initWithPublisher:@""
                              name:@""
                    currentVersion:@""
                     latestVersion:@""
                   updateAvailable:NO
                     latestRelease:@{}
                checkedAtUnixMillis:0];
}

@end

static OrenAVMPackageUpdateStatus* OrenAVMPackageUpdateStatusFromDictionary(NSDictionary<NSString*, id>* status,
                                                                            int64_t checkedAtUnixMillis,
                                                                            NSError** error) {
    NSString* publisher = OrenAVMPackageString(status, @"publisher");
    NSString* name = OrenAVMPackageString(status, @"name");
    NSString* currentVersion = OrenAVMPackageString(status, @"current_version") ?: @"";
    NSString* latestVersion = OrenAVMPackageString(status, @"latest_version") ?: @"";
    NSNumber* updateAvailable = OrenAVMPackageNumber(status, @"update_available");
    id latestRaw = status[@"latest_release"];
    NSDictionary<NSString*, id>* latestRelease = [latestRaw isKindOfClass:[NSDictionary class]] ? (NSDictionary<NSString*, id>*)latestRaw : @{};
    NSNumber* persistedCheckedAt = OrenAVMPackageNumber(status, @"checked_at_unix_ms");
    if (checkedAtUnixMillis <= 0 && persistedCheckedAt) checkedAtUnixMillis = persistedCheckedAt.longLongValue;
    if (publisher.length == 0 || name.length == 0 || !updateAvailable || checkedAtUnixMillis <= 0) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update status is invalid");
        return nil;
    }
    return [[OrenAVMPackageUpdateStatus alloc] initWithPublisher:publisher
                                                           name:name
                                                 currentVersion:currentVersion
                                                  latestVersion:latestVersion
                                                updateAvailable:updateAvailable.boolValue
                                                  latestRelease:latestRelease
                                            checkedAtUnixMillis:checkedAtUnixMillis];
}

static NSDictionary<NSString*, id>* OrenAVMPackageUpdateStatusDictionary(OrenAVMPackageUpdateStatus* status) {
    if (!status) return nil;
    return @{
        @"publisher": status.publisher ?: @"",
        @"name": status.name ?: @"",
        @"current_version": status.currentVersion ?: @"",
        @"latest_version": status.latestVersion ?: @"",
        @"update_available": @(status.updateAvailable),
        @"latest_release": status.latestRelease ?: @{},
        @"checked_at_unix_ms": @(status.checkedAtUnixMillis)
    };
}

static BOOL OrenAVMPackageWriteLastUpdateStatus(NSURL* packageRoot,
                                                OrenAVMPackageUpdateStatus* status,
                                                NSError** error) {
    NSURL* metaURL = OrenAVMPackageInstallMetadataURL(packageRoot);
    if (!metaURL || !status) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update history path is invalid");
    NSDictionary* metadata = OrenAVMPackageReadInstallMetadata(packageRoot, error);
    if (!metadata) return NO;
    NSMutableDictionary<NSString*, id>* out = [metadata mutableCopy];
    out[@"last_update_check"] = OrenAVMPackageUpdateStatusDictionary(status);
    NSData* data = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    return [data writeToURL:metaURL options:NSDataWritingAtomic error:error];
}

@implementation OrenAVMPackageStore

+ (NSString*)sha256HexForData:(NSData*)data {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString* out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2u];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

- (OrenAVMPackage*)loadPackageAtDirectoryURL:(NSURL*)directoryURL error:(NSError**)error {
    if (!directoryURL.isFileURL) return nil;
    NSURL* manifestURL = [directoryURL URLByAppendingPathComponent:@"package.json" isDirectory:NO];
    NSData* manifestData = [NSData dataWithContentsOfURL:manifestURL options:0 error:error];
    if (!manifestData) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package manifest must be a JSON object");
        return nil;
    }
    NSDictionary<NSString*, id>* manifest = (NSDictionary<NSString*, id>*)json;
    NSString* schema = OrenAVMPackageString(manifest, @"schema");
    NSString* name = OrenAVMPackageString(manifest, @"name");
    NSString* publisher = OrenAVMPackageString(manifest, @"publisher");
    NSString* version = OrenAVMPackageString(manifest, @"version");
    NSString* entry = OrenAVMPackageString(manifest, @"entry_obc");
    NSString* wantHash = OrenAVMPackageString(manifest, @"obc_sha256");
    NSNumber* abiMin = OrenAVMPackageNumber(manifest, @"avm_abi_min");
    if (![schema isEqualToString:@"oren.obc.package.v0"] || name.length == 0 ||
        publisher.length == 0 || version.length == 0 || entry.length == 0 || wantHash.length != 64 ||
        !abiMin || abiMin.unsignedIntValue > AVM_EMBED_ABI_VERSION || !OrenAVMPackagePathIsSafe(entry)) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package manifest is invalid or unsupported");
        return nil;
    }
    NSURL* obcURL = [directoryURL URLByAppendingPathComponent:entry isDirectory:NO];
    NSData* obcData = [NSData dataWithContentsOfURL:obcURL options:0 error:error];
    if (!obcData) return nil;
    NSString* gotHash = [OrenAVMPackageStore sha256HexForData:obcData];
    if (![gotHash isEqualToString:wantHash.lowercaseString]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package bytecode hash mismatch");
        return nil;
    }
    NSArray<NSString*>* capabilities = @[];
    id caps = manifest[@"capabilities"];
    if ([caps isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString*>* clean = [NSMutableArray array];
        for (id cap in (NSArray*)caps) {
            if (![cap isKindOfClass:[NSString class]] || OrenAVMPackageDomainForCapability(cap) == 0) {
                OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package has unsupported capability");
                return nil;
            }
            [clean addObject:[cap uppercaseString]];
        }
        capabilities = clean;
    }
    NSString* packageID = [NSString stringWithFormat:@"%@/%@/%@", publisher, name, version];
    return [[OrenAVMPackage alloc] initWithDirectoryURL:directoryURL
                                              manifest:manifest
                                               obcData:obcData
                                             packageID:packageID
                                                  name:name
                                             publisher:publisher
                                               version:version
                                          capabilities:capabilities];
}

- (OrenAVMPackageUpdateStatus*)packageUpdateStatusFromURL:(NSURL*)updateURL
                                             allowedHosts:(NSSet<NSString*>*)allowedHosts
                                           timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                    error:(NSError**)error {
    NSData* data = nil;
    if (!OrenAVMPackageFetchURLData(updateURL, allowedHosts, timeoutSeconds, &data, error)) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update status must be a JSON object");
        return nil;
    }
    return OrenAVMPackageUpdateStatusFromDictionary((NSDictionary<NSString*, id>*)json, OrenAVMPackageUnixMillis(), error);
}

- (OrenAVMPackageUpdateStatus*)packageUpdateStatusForPackage:(OrenAVMPackage*)package
                                                storeBaseURL:(NSURL*)storeBaseURL
                                                allowedHosts:(NSSet<NSString*>*)allowedHosts
                                              timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                       error:(NSError**)error {
    if (!package || package.publisher.length == 0 || package.name.length == 0 || package.version.length == 0) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update check requires a package");
        return nil;
    }
    NSURL* updateURL = OrenAVMPackageUpdateURL(storeBaseURL, package.publisher, package.name, package.version);
    if (!updateURL) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update URL is invalid");
        return nil;
    }
    return [self packageUpdateStatusFromURL:updateURL
                               allowedHosts:allowedHosts
                             timeoutSeconds:timeoutSeconds
                                      error:error];
}

- (OrenAVMPackageUpdateStatus*)packageUpdateStatusForInstalledPackage:(OrenAVMPackage*)package
                                                         allowedHosts:(NSSet<NSString*>*)allowedHosts
                                                       timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                                error:(NSError**)error {
    if (!package) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update check requires a package");
        return nil;
    }
    NSURL* indexURL = OrenAVMPackageReadInstallIndexURL(package.directoryURL, error);
    if (!indexURL) return nil;
    NSSet<NSString*>* effectiveAllowedHosts = OrenAVMPackageEffectiveAllowedHosts(allowedHosts, indexURL);
    OrenAVMPackageUpdateStatus* status = [self packageUpdateStatusForPackage:package
                                                                storeBaseURL:indexURL
                                                                allowedHosts:effectiveAllowedHosts
                                                              timeoutSeconds:timeoutSeconds
                                                                       error:error];
    if (status) (void)OrenAVMPackageWriteLastUpdateStatus(package.directoryURL, status, nil);
    return status;
}

- (OrenAVMPackageUpdateStatus*)lastKnownPackageUpdateStatusForInstalledPackage:(OrenAVMPackage*)package
                                                                         error:(NSError**)error {
    if (!package) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update history requires a package");
        return nil;
    }
    NSDictionary* metadata = OrenAVMPackageReadInstallMetadata(package.directoryURL, error);
    if (!metadata) return nil;
    id raw = metadata[@"last_update_check"];
    if (![raw isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update history is missing");
        return nil;
    }
    return OrenAVMPackageUpdateStatusFromDictionary((NSDictionary<NSString*, id>*)raw, 0, error);
}

- (OrenAVMPackage*)downloadUpdateForInstalledPackage:(OrenAVMPackage*)package
                            destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                       allowedHosts:(NSSet<NSString*>*)allowedHosts
                                     timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                        trustBundle:(OrenAVMOBCTrustBundle*)trustBundle
                                              error:(NSError**)error {
    if (!package || !destinationDirectoryURL.isFileURL || !trustBundle) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package update install requires a package, destination, and trust bundle");
        return nil;
    }
    NSURL* indexURL = OrenAVMPackageReadInstallIndexURL(package.directoryURL, error);
    if (!indexURL) return nil;
    NSSet<NSString*>* effectiveAllowedHosts = OrenAVMPackageEffectiveAllowedHosts(allowedHosts, indexURL);
    OrenAVMPackageUpdateStatus* status = [self packageUpdateStatusForPackage:package
                                                                storeBaseURL:indexURL
                                                                allowedHosts:effectiveAllowedHosts
                                                              timeoutSeconds:timeoutSeconds
                                                                       error:error];
    if (!status) return nil;
    (void)OrenAVMPackageWriteLastUpdateStatus(package.directoryURL, status, nil);
    if (!status.updateAvailable || status.latestVersion.length == 0) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package is already current");
        return nil;
    }
    NSString* packageID = [NSString stringWithFormat:@"%@/%@", package.publisher, package.name];
    return [self downloadPackageFromSignedIndexURL:indexURL
                                        packageID:packageID
                                          version:status.latestVersion
                          destinationDirectoryURL:destinationDirectoryURL
                                     allowedHosts:effectiveAllowedHosts
                                   timeoutSeconds:timeoutSeconds
                                      trustBundle:trustBundle
                                    installPolicy:OrenAVMPackageInstallPolicyFailIfInstalled
                                            error:error];
}

- (OrenAVMPackage*)downloadPackageFromIndexURL:(NSURL*)indexURL
                                     packageID:(NSString*)packageID
                                       version:(NSString*)version
                       destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                  allowedHosts:(NSSet<NSString*>*)allowedHosts
                                timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                         error:(NSError**)error {
    return [self downloadPackageFromIndexURL:indexURL
                                   packageID:packageID
                                     version:version
                     destinationDirectoryURL:destinationDirectoryURL
                                allowedHosts:allowedHosts
                              timeoutSeconds:timeoutSeconds
                  trustedPublisherPublicKeys:nil
                                       error:error];
}

- (OrenAVMPackage*)downloadPackageFromIndexURL:(NSURL*)indexURL
                                     packageID:(NSString*)packageID
                                       version:(NSString*)version
                       destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                  allowedHosts:(NSSet<NSString*>*)allowedHosts
                                timeoutSeconds:(NSTimeInterval)timeoutSeconds
                    trustedPublisherPublicKeys:(NSDictionary<NSString*, NSData*>*)trustedPublisherPublicKeys
                                         error:(NSError**)error {
    return [self downloadPackageFromSignedIndexURL:indexURL
                                         packageID:packageID
                                           version:version
                           destinationDirectoryURL:destinationDirectoryURL
                                      allowedHosts:allowedHosts
                                    timeoutSeconds:timeoutSeconds
                             trustedIndexPublicKey:nil
                        trustedPublisherPublicKeys:trustedPublisherPublicKeys
                                             error:error];
}

- (OrenAVMPackage*)downloadPackageFromSignedIndexURL:(NSURL*)indexURL
                                           packageID:(NSString*)packageID
                                             version:(NSString*)version
                             destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                        allowedHosts:(NSSet<NSString*>*)allowedHosts
                                      timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                          trustBundle:(OrenAVMOBCTrustBundle*)trustBundle
                                               error:(NSError**)error {
    return [self downloadPackageFromSignedIndexURL:indexURL
                                         packageID:packageID
                                           version:version
                           destinationDirectoryURL:destinationDirectoryURL
                                      allowedHosts:allowedHosts
                                    timeoutSeconds:timeoutSeconds
                                       trustBundle:trustBundle
                                     installPolicy:OrenAVMPackageInstallPolicyReplace
                                             error:error];
}

- (OrenAVMPackage*)downloadPackageFromSignedIndexURL:(NSURL*)indexURL
                                           packageID:(NSString*)packageID
                                             version:(NSString*)version
                             destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                        allowedHosts:(NSSet<NSString*>*)allowedHosts
                                      timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                         trustBundle:(OrenAVMOBCTrustBundle*)trustBundle
                                       installPolicy:(OrenAVMPackageInstallPolicy)installPolicy
                                               error:(NSError**)error {
    if (!trustBundle || trustBundle.defaultStorePublicKey.length == 0) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC trust bundle is required");
        return nil;
    }
    return [self downloadPackageFromSignedIndexURL:indexURL
                                         packageID:packageID
                                           version:version
                           destinationDirectoryURL:destinationDirectoryURL
                                      allowedHosts:allowedHosts
                                    timeoutSeconds:timeoutSeconds
                             trustedIndexPublicKey:trustBundle.defaultStorePublicKey
                        trustedPublisherPublicKeys:trustBundle.publisherPublicKeys
                                     installPolicy:installPolicy
                                             error:error];
}

- (OrenAVMPackage*)downloadPackageFromSignedIndexURL:(NSURL*)indexURL
                                           packageID:(NSString*)packageID
                                             version:(NSString*)version
                             destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                        allowedHosts:(NSSet<NSString*>*)allowedHosts
                                      timeoutSeconds:(NSTimeInterval)timeoutSeconds
                               trustedIndexPublicKey:(NSData*)trustedIndexPublicKey
                          trustedPublisherPublicKeys:(NSDictionary<NSString*, NSData*>*)trustedPublisherPublicKeys
                                               error:(NSError**)error {
    return [self downloadPackageFromSignedIndexURL:indexURL
                                         packageID:packageID
                                           version:version
                           destinationDirectoryURL:destinationDirectoryURL
                                      allowedHosts:allowedHosts
                                    timeoutSeconds:timeoutSeconds
                             trustedIndexPublicKey:trustedIndexPublicKey
                        trustedPublisherPublicKeys:trustedPublisherPublicKeys
                                     installPolicy:OrenAVMPackageInstallPolicyReplace
                                             error:error];
}

- (OrenAVMPackage*)downloadPackageFromSignedIndexURL:(NSURL*)indexURL
                                           packageID:(NSString*)packageID
                                             version:(NSString*)version
                             destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                        allowedHosts:(NSSet<NSString*>*)allowedHosts
                                      timeoutSeconds:(NSTimeInterval)timeoutSeconds
                               trustedIndexPublicKey:(NSData*)trustedIndexPublicKey
                          trustedPublisherPublicKeys:(NSDictionary<NSString*, NSData*>*)trustedPublisherPublicKeys
                                       installPolicy:(OrenAVMPackageInstallPolicy)installPolicy
                                               error:(NSError**)error {
    if (!indexURL || packageID.length == 0 || !destinationDirectoryURL.isFileURL) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"index URL, package id, and destination directory are required");
        return nil;
    }
    if (installPolicy != OrenAVMPackageInstallPolicyReplace &&
        installPolicy != OrenAVMPackageInstallPolicyKeepExisting &&
        installPolicy != OrenAVMPackageInstallPolicyFailIfInstalled) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"unsupported OBC package install policy");
        return nil;
    }
    NSData* indexData = nil;
    if (!OrenAVMPackageFetchURLData(indexURL, allowedHosts, timeoutSeconds, &indexData, error)) return nil;
    if (trustedIndexPublicKey) {
        NSURL* signatureURL = [[indexURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[indexURL.lastPathComponent stringByAppendingString:@".sig"]];
        NSData* signatureData = nil;
        if (!signatureURL || !OrenAVMPackageFetchURLData(signatureURL, allowedHosts, timeoutSeconds, &signatureData, error)) return nil;
        if (!OrenAVMPackageVerifyP256Signature(trustedIndexPublicKey, indexData, signatureData)) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC store index signature verification failed");
            return nil;
        }
    }
    id indexJSON = [NSJSONSerialization JSONObjectWithData:indexData options:0 error:error];
    if (![indexJSON isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC store index must be a JSON object");
        return nil;
    }
    NSDictionary* index = (NSDictionary*)indexJSON;
    if (![OrenAVMPackageString(index, @"schema") isEqualToString:@"oren.obc.store.index.v0"]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"unsupported OBC store index schema");
        return nil;
    }
    NSArray* packages = [index[@"packages"] isKindOfClass:[NSArray class]] ? index[@"packages"] : nil;
    NSDictionary* entry = nil;
    for (id item in packages) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary* candidate = (NSDictionary*)item;
        NSString* eid = OrenAVMPackageString(candidate, @"id");
        NSString* eversion = OrenAVMPackageString(candidate, @"version");
        if ([eid isEqualToString:packageID] && (version.length == 0 || [eversion isEqualToString:version])) {
            entry = candidate;
            break;
        }
    }
    if (!entry) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"package not found in OBC store index");
        return nil;
    }
    NSString* manifestPath = OrenAVMPackageString(entry, @"manifest");
    NSString* manifestHash = OrenAVMPackageString(entry, @"manifest_sha256");
    NSURL* manifestURL = OrenAVMPackageResolveStoreURL(indexURL, manifestPath);
    if (!manifestURL || manifestHash.length != 64) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC store index package entry is invalid");
        return nil;
    }
    NSData* manifestData = nil;
    if (!OrenAVMPackageFetchURLData(manifestURL, allowedHosts, timeoutSeconds, &manifestData, error)) return nil;
    if (![[OrenAVMPackageStore sha256HexForData:manifestData] isEqualToString:manifestHash.lowercaseString]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package manifest hash mismatch");
        return nil;
    }
    if (trustedPublisherPublicKeys.count > 0) {
        NSString* publisherID = [[packageID componentsSeparatedByString:@"/"] firstObject];
        NSData* publisherKey = trustedPublisherPublicKeys[publisherID];
        NSString* signatureAlg = OrenAVMPackageString(entry, @"signature_alg");
        NSString* signatureHex = OrenAVMPackageString(entry, @"signature_p256_sha256_der_hex");
        NSData* signature = OrenAVMPackageDecodeHex(signatureHex);
        NSData* signedMessage = [manifestHash.lowercaseString dataUsingEncoding:NSUTF8StringEncoding];
        if (!publisherKey || ![signatureAlg isEqualToString:@"p256-sha256-der"] || !signature ||
            !OrenAVMPackageVerifyP256Signature(publisherKey, signedMessage, signature)) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package signature verification failed");
            return nil;
        }
    }
    id manifestJSON = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:error];
    if (![manifestJSON isKindOfClass:[NSDictionary class]]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package manifest must be a JSON object");
        return nil;
    }
    NSDictionary* manifest = (NSDictionary*)manifestJSON;
    NSString* publisher = OrenAVMPackageString(manifest, @"publisher");
    NSString* name = OrenAVMPackageString(manifest, @"name");
    NSString* manifestVersion = OrenAVMPackageString(manifest, @"version");
    NSString* entryObc = OrenAVMPackageString(manifest, @"entry_obc");
    if (publisher.length == 0 || name.length == 0 || manifestVersion.length == 0 ||
        !OrenAVMPackagePathIsSafe(entryObc) || ![[NSString stringWithFormat:@"%@/%@", publisher, name] isEqualToString:packageID]) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package manifest identity is invalid");
        return nil;
    }
    NSURL* packageRoot = OrenAVMPackageAppendSafeRelativePath(destinationDirectoryURL, packageID, YES);
    packageRoot = OrenAVMPackageAppendSafeRelativePath(packageRoot, manifestVersion, YES);
    if (!packageRoot) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package destination path is invalid");
        return nil;
    }
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL packageExists = [fm fileExistsAtPath:packageRoot.path];
    if (packageExists) {
        if (installPolicy == OrenAVMPackageInstallPolicyKeepExisting) {
            if (!OrenAVMPackageWriteInstallMetadata(packageRoot, indexURL, manifest, error)) return nil;
            return [self loadPackageAtDirectoryURL:packageRoot error:error];
        }
        if (installPolicy == OrenAVMPackageInstallPolicyFailIfInstalled) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package version is already installed");
            return nil;
        }
        if (installPolicy != OrenAVMPackageInstallPolicyReplace) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"unsupported OBC package install policy");
            return nil;
        }
    }
    NSString* tmpName = [NSString stringWithFormat:@".%@.tmp.%@", manifestVersion, [[NSUUID UUID] UUIDString]];
    NSURL* packageTmpRoot = OrenAVMPackageAppendSafeRelativePath([packageRoot URLByDeletingLastPathComponent], tmpName, YES);
    if (!packageTmpRoot) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package destination path is invalid");
        return nil;
    }
    (void)[fm removeItemAtURL:packageTmpRoot error:nil];
    NSString* bundlePath = OrenAVMPackageString(entry, @"bundle");
    NSString* bundleHash = OrenAVMPackageString(entry, @"bundle_sha256");
    NSString* bundleMediaType = OrenAVMPackageString(entry, @"bundle_media_type");
    if (bundlePath.length > 0 || bundleHash.length > 0) {
        if (bundlePath.length == 0 || bundleHash.length != 64 ||
            (bundleMediaType.length > 0 && ![bundleMediaType isEqualToString:@"application/vnd.oren.obc.release+zip"])) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC store index bundle entry is invalid");
            return nil;
        }
        NSURL* bundleURL = OrenAVMPackageResolveStoreURL(indexURL, bundlePath);
        NSData* bundleData = nil;
        if (!bundleURL || !OrenAVMPackageFetchURLData(bundleURL, allowedHosts, timeoutSeconds, &bundleData, error)) return nil;
        if (![[OrenAVMPackageStore sha256HexForData:bundleData] isEqualToString:bundleHash.lowercaseString]) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle hash mismatch");
            return nil;
        }
        if (![fm createDirectoryAtURL:packageTmpRoot withIntermediateDirectories:YES attributes:nil error:error]) return nil;
        if (!OrenAVMPackageExtractReleaseBundle(bundleData, packageTmpRoot, error)) return nil;
        NSData* stagedManifestData = [NSData dataWithContentsOfURL:[packageTmpRoot URLByAppendingPathComponent:@"package.json" isDirectory:NO] options:0 error:error];
        if (!stagedManifestData) return nil;
        if (![[OrenAVMPackageStore sha256HexForData:stagedManifestData] isEqualToString:manifestHash.lowercaseString]) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC release bundle manifest hash mismatch");
            return nil;
        }
    } else {
        NSURL* obcURL = OrenAVMPackageResolveStoreURL(manifestURL, entryObc);
        NSData* obcData = nil;
        if (!OrenAVMPackageFetchURLData(obcURL, allowedHosts, timeoutSeconds, &obcData, error)) return nil;
        NSURL* obcOutURL = OrenAVMPackageAppendSafeRelativePath(packageTmpRoot, entryObc, NO);
        if (!obcOutURL) {
            OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package destination path is invalid");
            return nil;
        }
        if (![fm createDirectoryAtURL:[obcOutURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:error]) return nil;
        if (![manifestData writeToURL:[packageTmpRoot URLByAppendingPathComponent:@"package.json" isDirectory:NO] options:NSDataWritingAtomic error:error]) return nil;
        if (![obcData writeToURL:obcOutURL options:NSDataWritingAtomic error:error]) return nil;
        id assets = manifest[@"assets"];
        if ([assets isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray*)assets) {
                if (![item isKindOfClass:[NSDictionary class]]) {
                    OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package asset entries must be objects");
                    return nil;
                }
                NSDictionary* asset = (NSDictionary*)item;
                NSString* assetPath = OrenAVMPackageString(asset, @"path");
                NSString* assetHash = OrenAVMPackageString(asset, @"sha256");
                if (!OrenAVMPackagePathIsSafe(assetPath) || assetHash.length != 64) {
                    OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package asset entry is invalid");
                    return nil;
                }
                NSURL* assetURL = OrenAVMPackageResolveStoreURL(manifestURL, assetPath);
                NSURL* assetOutURL = OrenAVMPackageAppendSafeRelativePath(packageTmpRoot, assetPath, NO);
                if (!assetURL || !assetOutURL) {
                    OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package asset path is invalid");
                    return nil;
                }
                NSData* assetData = nil;
                if (!OrenAVMPackageFetchURLData(assetURL, allowedHosts, timeoutSeconds, &assetData, error)) return nil;
                if (![[OrenAVMPackageStore sha256HexForData:assetData] isEqualToString:assetHash.lowercaseString]) {
                    OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package asset hash mismatch");
                    return nil;
                }
                if (![fm createDirectoryAtURL:[assetOutURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:error]) return nil;
                if (![assetData writeToURL:assetOutURL options:NSDataWritingAtomic error:error]) return nil;
            }
        }
    }
    if (!OrenAVMPackageWriteInstallMetadata(packageTmpRoot, indexURL, manifest, error)) {
        (void)[fm removeItemAtURL:packageTmpRoot error:nil];
        return nil;
    }
    OrenAVMPackage* staged = [self loadPackageAtDirectoryURL:packageTmpRoot error:error];
    if (!staged) {
        (void)[fm removeItemAtURL:packageTmpRoot error:nil];
        return nil;
    }
    if (![staged.packageID isEqualToString:[NSString stringWithFormat:@"%@/%@", packageID, manifestVersion]]) {
        (void)[fm removeItemAtURL:packageTmpRoot error:nil];
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package staged identity mismatch");
        return nil;
    }
    (void)[fm removeItemAtURL:packageRoot error:nil];
    if (![fm createDirectoryAtURL:[packageRoot URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    if (![fm moveItemAtURL:packageTmpRoot toURL:packageRoot error:error]) return nil;
    return [self loadPackageAtDirectoryURL:packageRoot error:error];
}

- (OrenAVMRuntimeConfig*)runtimeConfigForPackage:(OrenAVMPackage*)package error:(NSError**)error {
    if (!package) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"OBC package is nil");
        return nil;
    }
    NSString* timeMode = OrenAVMPackageString(package.manifest, @"time_mode") ?: @"deterministic";
    OrenAVMRuntimeConfig* cfg = [timeMode isEqualToString:@"interactive"] ?
        [OrenAVMRuntimeConfig interactiveAppDefaults] : [OrenAVMRuntimeConfig deterministicDefaults];
    uint64_t domains = 0;
    for (NSString* cap in package.capabilities) domains |= OrenAVMPackageDomainForCapability(cap);
    if (domains == 0) domains = OrenAVMDomainCore | OrenAVMDomainExit;
    cfg.allowedDomains = domains;
    id budgets = package.manifest[@"budgets"];
    if ([budgets isKindOfClass:[NSDictionary class]]) {
        NSNumber* gas = [(NSDictionary*)budgets objectForKey:@"gas"];
        NSNumber* heap = [(NSDictionary*)budgets objectForKey:@"heap_bytes"];
        NSNumber* io = [(NSDictionary*)budgets objectForKey:@"io_bytes"];
        NSNumber* frames = [(NSDictionary*)budgets objectForKey:@"frame_commands"];
        if ([gas isKindOfClass:[NSNumber class]] && gas.unsignedLongLongValue > 0) cfg.gasLimit = gas.unsignedLongLongValue;
        if ([heap isKindOfClass:[NSNumber class]] && heap.unsignedLongLongValue > 0) cfg.heapLimitBytes = heap.unsignedLongLongValue;
        if ([io isKindOfClass:[NSNumber class]] && io.unsignedLongLongValue > 0) cfg.ioLimitBytes = io.unsignedLongLongValue;
        if ([frames isKindOfClass:[NSNumber class]] && frames.unsignedIntValue > 0) cfg.frameLimit = frames.unsignedIntValue;
    }
    return cfg;
}

- (BOOL)mountPackageAssetsForPackage:(OrenAVMPackage*)package runtime:(OrenAVMRuntime*)runtime error:(NSError**)error {
    if (!package || !runtime) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"package and runtime are required");
    id mounts = package.manifest[@"vfs_mounts"];
    if (![mounts isKindOfClass:[NSArray class]]) return YES;
    for (id item in (NSArray*)mounts) {
        if (![item isKindOfClass:[NSDictionary class]]) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"vfs_mounts entries must be objects");
        NSDictionary* m = (NSDictionary*)item;
        NSString* virtualPath = [m[@"virtual"] isKindOfClass:[NSString class]] ? m[@"virtual"] : nil;
        NSString* packagePath = [m[@"package_path"] isKindOfClass:[NSString class]] ? m[@"package_path"] : nil;
        BOOL readOnly = ![m[@"read_only"] isKindOfClass:[NSNumber class]] || [m[@"read_only"] boolValue];
        if (virtualPath.length == 0 || packagePath.length == 0 || !readOnly || !OrenAVMPackagePathIsSafe(packagePath)) {
            return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"unsupported or unsafe package VFS mount");
        }
        NSURL* source = [package.directoryURL URLByAppendingPathComponent:packagePath isDirectory:NO];
        NSNumber* isDir = nil;
        if (![source getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:error]) return NO;
        if (isDir.boolValue) {
            if (![runtime mountDirectoryURL:source atVFSRoot:virtualPath error:error]) return NO;
        } else {
            if (![runtime mountFileURL:source atVFSPath:virtualPath error:error]) return NO;
        }
    }
    return YES;
}

- (OrenAVMRunResult*)runPackage:(OrenAVMPackage*)package runtime:(OrenAVMRuntime*)runtime error:(NSError**)error {
    if (![self mountPackageAssetsForPackage:package runtime:runtime error:error]) return nil;
    return [runtime runOBCData:package.obcData error:error];
}

- (NSArray<NSString*>*)listInstalledPackageIDsInDirectoryURL:(NSURL*)installRootURL error:(NSError**)error {
    if (!installRootURL.isFileURL) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"install root must be a file URL");
        return nil;
    }
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray<NSURL*>* publishers = [fm contentsOfDirectoryAtURL:installRootURL
                                    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                         error:error];
    if (!publishers) return @[];
    NSMutableArray<NSString*>* out = [NSMutableArray array];
    for (NSURL* publisherURL in publishers) {
        NSNumber* publisherIsDir = nil;
        if (![publisherURL getResourceValue:&publisherIsDir forKey:NSURLIsDirectoryKey error:nil] || !publisherIsDir.boolValue) continue;
        NSString* publisher = publisherURL.lastPathComponent;
        NSArray<NSURL*>* names = [fm contentsOfDirectoryAtURL:publisherURL includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        for (NSURL* nameURL in names) {
            NSNumber* nameIsDir = nil;
            if (![nameURL getResourceValue:&nameIsDir forKey:NSURLIsDirectoryKey error:nil] || !nameIsDir.boolValue) continue;
            NSString* name = nameURL.lastPathComponent;
            NSArray<NSURL*>* versions = [fm contentsOfDirectoryAtURL:nameURL includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
            for (NSURL* versionURL in versions) {
                NSNumber* versionIsDir = nil;
                if (![versionURL getResourceValue:&versionIsDir forKey:NSURLIsDirectoryKey error:nil] || !versionIsDir.boolValue) continue;
                [out addObject:[NSString stringWithFormat:@"%@/%@/%@", publisher, name, versionURL.lastPathComponent]];
            }
        }
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

- (OrenAVMPackage*)loadInstalledPackageInDirectoryURL:(NSURL*)installRootURL
                                           packageID:(NSString*)packageID
                                             version:(NSString*)version
                                               error:(NSError**)error {
    NSURL* packageRoot = OrenAVMPackageAppendSafeRelativePath(installRootURL, packageID, YES);
    packageRoot = OrenAVMPackageAppendSafeRelativePath(packageRoot, version, YES);
    if (!packageRoot) {
        OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"installed package path is invalid");
        return nil;
    }
    return [self loadPackageAtDirectoryURL:packageRoot error:error];
}

- (BOOL)removeInstalledPackageInDirectoryURL:(NSURL*)installRootURL
                                   packageID:(NSString*)packageID
                                     version:(NSString*)version
                                       error:(NSError**)error {
    NSURL* packageRoot = OrenAVMPackageAppendSafeRelativePath(installRootURL, packageID, YES);
    packageRoot = OrenAVMPackageAppendSafeRelativePath(packageRoot, version, YES);
    if (!packageRoot) return OrenAVMPackageAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"installed package path is invalid");
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:packageRoot.path]) return YES;
    return [fm removeItemAtURL:packageRoot error:error];
}

@end
