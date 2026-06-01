#import "OrenAVMKit.h"

static BOOL OrenAVMPermissionAssignError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"AVM permission error"}];
    }
    return NO;
}

static NSString* OrenAVMPermissionCleanString(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString*)value : @"";
}

static NSString* OrenAVMPermissionKey(NSString* domain, NSString* action, NSString* detail) {
    NSString* cleanDomain = (domain ?: @"").uppercaseString;
    NSString* cleanAction = (action ?: @"").lowercaseString;
    NSString* cleanDetail = detail ?: @"";
    return [NSString stringWithFormat:@"%@\n%@\n%@", cleanDomain, cleanAction, cleanDetail];
}

static NSDictionary<NSString*, NSString*>* OrenAVMPermissionEntry(NSString* domain, NSString* action, NSString* detail) {
    return @{
        @"domain": (domain ?: @"").uppercaseString,
        @"action": (action ?: @"").lowercaseString,
        @"detail": detail ?: @"",
    };
}

static NSString* OrenAVMPermissionNetworkHostFromDetail(NSString* detail) {
    if (detail.length == 0) return nil;
    NSURL* url = [NSURL URLWithString:detail];
    if (url.host.length > 0) return url.host;
    NSRange scheme = [detail rangeOfString:@"://"];
    if (scheme.location != NSNotFound) {
        NSString* authority = [detail substringFromIndex:scheme.location + scheme.length];
        NSRange slash = [authority rangeOfString:@"/"];
        if (slash.location != NSNotFound) authority = [authority substringToIndex:slash.location];
        if ([authority hasPrefix:@"["]) {
            NSRange close = [authority rangeOfString:@"]"];
            if (close.location != NSNotFound && close.location > 1) {
                return [authority substringWithRange:NSMakeRange(1, close.location - 1)];
            }
        }
        NSRange colonInAuthority = [authority rangeOfString:@":"];
        NSString* host = colonInAuthority.location == NSNotFound ? authority : [authority substringToIndex:colonInAuthority.location];
        return host.length > 0 ? host : nil;
    }
    NSRange colon = [detail rangeOfString:@":"];
    NSString* host = colon.location == NSNotFound ? detail : [detail substringToIndex:colon.location];
    return host.length > 0 ? host : nil;
}

@interface OrenAVMPermissionPrompt ()

@property(nonatomic, readwrite, copy) NSString* domain;
@property(nonatomic, readwrite, copy) NSString* action;
@property(nonatomic, readwrite, copy) NSString* detail;
@property(nonatomic, readwrite) uint64_t sequence;
@property(nonatomic, readwrite, copy) NSString* title;
@property(nonatomic, readwrite, copy) NSString* message;
@property(nonatomic, readwrite, copy) NSString* riskLevel;
@property(nonatomic, readwrite, copy) NSString* networkHost;

@end

@implementation OrenAVMPermissionPrompt

+ (instancetype)promptWithPermissionRequest:(NSDictionary<NSString*, id>*)request error:(NSError**)error {
    if (![request isKindOfClass:[NSDictionary class]]) {
        OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                     @"permission request must be a dictionary");
        return nil;
    }
    NSString* domain = OrenAVMPermissionCleanString(request[@"domain"]).uppercaseString;
    NSString* action = OrenAVMPermissionCleanString(request[@"action"]).lowercaseString;
    NSString* detail = OrenAVMPermissionCleanString(request[@"detail"]);
    if (domain.length == 0 || action.length == 0) {
        OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                     @"permission prompt requires domain and action");
        return nil;
    }
    uint64_t sequence = 0;
    id sequenceValue = request[@"sequence"];
    if (sequenceValue && sequenceValue != (id)[NSNull null]) {
        if (![sequenceValue isKindOfClass:[NSNumber class]]) {
            OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                         @"permission prompt sequence must be numeric");
            return nil;
        }
        sequence = [(NSNumber*)sequenceValue unsignedLongLongValue];
    }

    OrenAVMPermissionPrompt* prompt = [[OrenAVMPermissionPrompt alloc] init];
    prompt.domain = domain;
    prompt.action = action;
    prompt.detail = detail;
    prompt.sequence = sequence;

    if ([domain isEqualToString:@"NET"] && [action isEqualToString:@"connect"]) {
        NSString* host = OrenAVMPermissionNetworkHostFromDetail(detail);
        prompt.networkHost = host;
        prompt.title = @"Allow Network Access?";
        prompt.riskLevel = @"network";
        if (host.length > 0) {
            prompt.message = [NSString stringWithFormat:
                @"This OBC program wants to connect to %@. Approve only if you trust the package and endpoint.",
                host];
        } else {
            prompt.message = @"This OBC program wants to open a network connection. Approve only if you trust the package.";
        }
    } else if ([domain isEqualToString:@"FS"]) {
        prompt.title = @"Allow File Access?";
        prompt.riskLevel = @"host-data";
        prompt.message = @"This OBC program wants to access host-provided files or package assets. Review the path before approving.";
    } else if ([domain isEqualToString:@"PROC"]) {
        prompt.title = @"Allow Host Process Action?";
        prompt.riskLevel = @"host-process";
        prompt.message = @"This OBC program wants to request a host-managed process or job action. Approve only for trusted packages.";
    } else {
        prompt.title = @"Allow AVM Permission?";
        prompt.riskLevel = @"custom";
        prompt.message = [NSString stringWithFormat:
            @"This OBC program requests %@/%@%@%@.",
            domain,
            action,
            detail.length > 0 ? @" for " : @"",
            detail.length > 0 ? detail : @""];
    }
    return prompt;
}

- (NSDictionary<NSString*, id>*)permissionRequest {
    return @{
        @"domain": self.domain ?: @"",
        @"action": self.action ?: @"",
        @"detail": self.detail ?: @"",
        @"sequence": @(self.sequence),
    };
}

@end

@interface OrenAVMPermissionGrantStore ()

@property(nonatomic, strong) NSMutableDictionary<NSString*, NSDictionary<NSString*, NSString*>*>* grantsByKey;

@end

@implementation OrenAVMPermissionGrantStore

- (instancetype)initWithStoreURL:(NSURL*)storeURL {
    self = [super init];
    if (self) {
        _storeURL = [storeURL copy];
        _grantsByKey = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)loadWithError:(NSError**)error {
    [self.grantsByKey removeAllObjects];
    if (!self.storeURL.isFileURL) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission grant store URL must be a file URL");
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.storeURL.path]) return YES;
    NSData* data = [NSData dataWithContentsOfURL:self.storeURL options:0 error:error];
    if (!data) return NO;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission grant store must be a JSON object");
    }
    NSDictionary<NSString*, id>* root = (NSDictionary<NSString*, id>*)json;
    if (![OrenAVMPermissionCleanString(root[@"schema"]) isEqualToString:@"oren.avm.permission.grants.v0"]) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission grant store schema is unsupported");
    }
    id grants = root[@"grants"];
    if (![grants isKindOfClass:[NSArray class]]) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission grant store grants must be an array");
    }
    for (id item in (NSArray*)grants) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                               @"permission grant entries must be objects");
        }
        NSDictionary<NSString*, id>* entry = (NSDictionary<NSString*, id>*)item;
        NSString* domain = OrenAVMPermissionCleanString(entry[@"domain"]);
        NSString* action = OrenAVMPermissionCleanString(entry[@"action"]);
        NSString* detail = OrenAVMPermissionCleanString(entry[@"detail"]);
        if (domain.length == 0 || action.length == 0) {
            return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                               @"permission grant entry is invalid");
        }
        NSDictionary<NSString*, NSString*>* clean = OrenAVMPermissionEntry(domain, action, detail);
        self.grantsByKey[OrenAVMPermissionKey(domain, action, detail)] = clean;
    }
    return YES;
}

- (BOOL)saveWithError:(NSError**)error {
    if (!self.storeURL.isFileURL) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission grant store URL must be a file URL");
    }
    NSURL* parent = [self.storeURL URLByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:parent
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) {
        return NO;
    }
    NSArray<NSString*>* keys = [self.grantsByKey.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray* grants = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString* key in keys) [grants addObject:self.grantsByKey[key]];
    NSDictionary* root = @{
        @"schema": @"oren.avm.permission.grants.v0",
        @"grants": grants,
    };
    NSData* data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingSortedKeys error:error];
    if (!data) return NO;
    return [data writeToURL:self.storeURL options:NSDataWritingAtomic error:error];
}

- (BOOL)setGranted:(BOOL)granted domain:(NSString*)domain action:(NSString*)action detail:(NSString*)detail error:(NSError**)error {
    if (domain.length == 0 || action.length == 0) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission grant requires domain and action");
    }
    NSString* key = OrenAVMPermissionKey(domain, action, detail);
    if (granted) {
        self.grantsByKey[key] = OrenAVMPermissionEntry(domain, action, detail);
    } else {
        [self.grantsByKey removeObjectForKey:key];
    }
    return [self saveWithError:error];
}

- (BOOL)isGrantedForDomain:(NSString*)domain action:(NSString*)action detail:(NSString*)detail {
    return self.grantsByKey[OrenAVMPermissionKey(domain, action, detail)] != nil;
}

- (NSSet<NSString*>*)allowedNetworkHosts {
    NSMutableSet<NSString*>* hosts = [NSMutableSet set];
    for (NSDictionary<NSString*, NSString*>* entry in self.grantsByKey.allValues) {
        if (![entry[@"domain"] isEqualToString:@"NET"]) continue;
        NSString* host = OrenAVMPermissionNetworkHostFromDetail(entry[@"detail"]);
        if (host.length > 0) [hosts addObject:host];
    }
    return hosts;
}

- (BOOL)applyNetworkGrantsToRuntime:(OrenAVMRuntime*)runtime timeoutSeconds:(NSTimeInterval)timeoutSeconds error:(NSError**)error {
    if (!runtime) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"runtime is required to apply network grants");
    }
    NSSet<NSString*>* hosts = [self allowedNetworkHosts];
    if (hosts.count == 0) return [runtime disableLiveNetworkWithError:error];
    return [runtime enableLiveNetworkWithAllowedHosts:hosts timeoutSeconds:timeoutSeconds error:error];
}

- (BOOL)recordDecisionForPermissionRequest:(NSDictionary<NSString*, id>*)request
                                   granted:(BOOL)granted
                                   runtime:(OrenAVMRuntime*)runtime
                            timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                      error:(NSError**)error {
    if (![request isKindOfClass:[NSDictionary class]]) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission request must be a dictionary");
    }
    NSString* domain = OrenAVMPermissionCleanString(request[@"domain"]);
    NSString* action = OrenAVMPermissionCleanString(request[@"action"]);
    NSString* detail = OrenAVMPermissionCleanString(request[@"detail"]);
    if (![self setGranted:granted domain:domain action:action detail:detail error:error]) return NO;
    if ([domain.uppercaseString isEqualToString:@"NET"] && runtime) {
        return [self applyNetworkGrantsToRuntime:runtime timeoutSeconds:timeoutSeconds error:error];
    }
    return YES;
}

- (BOOL)recordDecisionForPermissionPrompt:(OrenAVMPermissionPrompt*)prompt
                                  granted:(BOOL)granted
                                  runtime:(OrenAVMRuntime*)runtime
                           timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                     error:(NSError**)error {
    if (![prompt isKindOfClass:[OrenAVMPermissionPrompt class]]) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"permission prompt is required");
    }
    return [self recordDecisionForPermissionRequest:[prompt permissionRequest]
                                           granted:granted
                                           runtime:runtime
                                    timeoutSeconds:timeoutSeconds
                                             error:error];
}

- (BOOL)isGrantedForPermissionPrompt:(OrenAVMPermissionPrompt*)prompt {
    if (![prompt isKindOfClass:[OrenAVMPermissionPrompt class]]) return NO;
    return [self isGrantedForDomain:prompt.domain action:prompt.action detail:prompt.detail];
}

- (BOOL)applyPackagePermissionDefaults:(OrenAVMPackage*)package
                                runtime:(OrenAVMRuntime*)runtime
                         timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                  error:(NSError**)error {
    if (![package isKindOfClass:[OrenAVMPackage class]]) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"package is required to apply permission defaults");
    }
    id defaults = package.manifest[@"permission_defaults"];
    if (!defaults || defaults == (id)[NSNull null]) return YES;
    if (![defaults isKindOfClass:[NSArray class]]) {
        return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                           @"package permission_defaults must be an array");
    }

    NSMutableArray<NSDictionary<NSString*, id>*>* cleanDefaults = [NSMutableArray array];
    BOOL touchesNetwork = NO;
    for (id item in (NSArray*)defaults) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                               @"package permission default entries must be objects");
        }
        NSDictionary<NSString*, id>* entry = (NSDictionary<NSString*, id>*)item;
        id domainValue = entry[@"domain"];
        id actionValue = entry[@"action"];
        if (![domainValue isKindOfClass:[NSString class]] || ![actionValue isKindOfClass:[NSString class]]) {
            return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                               @"package permission default requires string domain and action");
        }
        NSString* domain = (NSString*)domainValue;
        NSString* action = (NSString*)actionValue;
        id detailValue = entry[@"detail"];
        NSString* detail = @"";
        if (detailValue && detailValue != (id)[NSNull null]) {
            if (![detailValue isKindOfClass:[NSString class]]) {
                return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                                   @"package permission default detail must be a string");
            }
            detail = (NSString*)detailValue;
        }
        if (domain.length == 0 || action.length == 0) {
            return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                               @"package permission default requires non-empty domain and action");
        }
        BOOL granted = YES;
        id grantedValue = entry[@"granted"];
        if (grantedValue && grantedValue != (id)[NSNull null]) {
            if (![grantedValue isKindOfClass:[NSNumber class]]) {
                return OrenAVMPermissionAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                                   @"package permission default granted must be boolean");
            }
            granted = [(NSNumber*)grantedValue boolValue];
        }
        if ([domain.uppercaseString isEqualToString:@"NET"]) touchesNetwork = YES;
        [cleanDefaults addObject:@{
            @"domain": domain,
            @"action": action,
            @"detail": detail,
            @"granted": @(granted),
        }];
    }

    for (NSDictionary<NSString*, id>* entry in cleanDefaults) {
        NSString* domain = (NSString*)entry[@"domain"];
        NSString* action = (NSString*)entry[@"action"];
        NSString* detail = (NSString*)entry[@"detail"];
        NSString* key = OrenAVMPermissionKey(domain, action, detail);
        if ([entry[@"granted"] boolValue]) {
            self.grantsByKey[key] = OrenAVMPermissionEntry(domain, action, detail);
        } else {
            [self.grantsByKey removeObjectForKey:key];
        }
    }
    if (![self saveWithError:error]) return NO;
    if (touchesNetwork && runtime) {
        return [self applyNetworkGrantsToRuntime:runtime timeoutSeconds:timeoutSeconds error:error];
    }
    return YES;
}

@end
