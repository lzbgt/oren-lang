<!--
{
  "availability" : [
    "iOS: 9.0.0 -",
    "iPadOS: 9.0.0 -",
    "macCatalyst: 13.1.0 -",
    "macOS: 10.11.0 -",
    "tvOS: 9.0.0 -",
    "visionOS: 1.0.0 -"
  ],
  "documentType" : "symbol",
  "framework" : "MetalKit",
  "identifier" : "/documentation/MetalKit/MTKView",
  "metadataVersion" : "0.1.0",
  "role" : "Class",
  "symbol" : {
    "kind" : "Class",
    "modules" : [
      "MetalKit"
    ],
    "preciseIdentifier" : "c:objc(cs)MTKView"
  },
  "title" : "MTKView"
}
-->

# MTKView

A specialized view that creates, configures, and displays Metal objects.

```
@MainActor class MTKView
```

## Overview

The [`MTKView`](/documentation/MetalKit/MTKView) class provides a default implementation of a Metal-aware view that you can use to render graphics using Metal and display them onscreen. When asked, the view provides a <doc://com.apple.documentation/documentation/Metal/MTLRenderPassDescriptor> object that points at a texture for you to render new contents into. Optionally, an [`MTKView`](/documentation/MetalKit/MTKView) can create depth and stencil textures for you and any intermediate textures needed for antialiasing. The view uses a <doc://com.apple.documentation/documentation/QuartzCore/CAMetalLayer> to manage the Metal drawable objects.

The view requires a <doc://com.apple.documentation/documentation/Metal/MTLDevice> object to manage the Metal objects it creates for you. You must set the [`device`](/documentation/MetalKit/MTKView/device) property and, optionally, modify the view’s drawable properties before drawing.

### Configuring the Drawing Behavior

The MTKView class supports three drawing modes:

- Timed updates: The view redraws its contents based on an internal timer. In this case, which is the default behavior, both ``doc://com.apple.metalkit/documentation/MetalKit/MTKView/isPaused`` and ``doc://com.apple.metalkit/documentation/MetalKit/MTKView/enableSetNeedsDisplay`` are set to <doc://com.apple.documentation/documentation/Swift/false>. Use this mode for games and other animated content that’s regularly updated.
- Draw notifications: The view redraws itself when something invalidates its contents, usually because of a call to <doc://com.apple.documentation/documentation/UIKit/UIView/setNeedsDisplay()> or some other view-related behavior. In this case, set ``doc://com.apple.metalkit/documentation/MetalKit/MTKView/isPaused`` and ``doc://com.apple.metalkit/documentation/MetalKit/MTKView/enableSetNeedsDisplay`` to <doc://com.apple.documentation/documentation/Swift/true>. Use this mode for apps with a more traditional workflow, where updates happen when data changes, but not on a regular timed interval.
- Explicit drawing: The view redraws its contents only when you explicitly call the ``doc://com.apple.metalkit/documentation/MetalKit/MTKView/draw()`` method. In this case, set ``doc://com.apple.metalkit/documentation/MetalKit/MTKView/isPaused`` to <doc://com.apple.documentation/documentation/Swift/true> and ``doc://com.apple.metalkit/documentation/MetalKit/MTKView/enableSetNeedsDisplay`` to <doc://com.apple.documentation/documentation/Swift/false>. Use this mode to create your own custom workflow.

### Drawing the View’s Contents

Regardless of drawing mode, when the view needs to update its contents, it calls the <doc://com.apple.documentation/documentation/AppKit/NSView/draw(_:)> method when that method has been overridden by a subclass, or [`draw(in:)`](/documentation/MetalKit/MTKViewDelegate/draw(in:)) on the view’s delegate if the subclass doesn’t override it. You should either subclass [`MTKView`](/documentation/MetalKit/MTKView) or provide a delegate, but not both.

In your drawing method, you obtain a render pass descriptor from the view, render into it, and then present the associated drawable.

### Obtaining a Drawable from a MetalKit View

Each [`MTKView`](/documentation/MetalKit/MTKView) is backed by a <doc://com.apple.documentation/documentation/QuartzCore/CAMetalLayer>. In your renderer, implement the [`MTKViewDelegate`](/documentation/MetalKit/MTKViewDelegate) protocol to interact with a MetalKit view. Call the MetalKit view’s [`currentRenderPassDescriptor`](/documentation/MetalKit/MTKView/currentRenderPassDescriptor) property to obtain a render pass descriptor configured for the current frame:

```swift
// BEGIN encoding your onscreen render pass.
// Obtain a render pass descriptor generated from the drawable's texture.
// (`currentRenderPassDescriptor` implicitly obtains the current drawable.)
// If there's a valid render pass descriptor, use it to render to the current drawable.
if let onscreenDescriptor = view.currentRenderPassDescriptor
```

When you read this property, Core Animation implicitly obtains a drawable for the current frame and stores it in the [`currentDrawable`](/documentation/MetalKit/MTKView/currentDrawable) property. It then configures a render pass descriptor to draw into that drawable, including any depth, stencil, and antialiasing textures as necessary. The view configures this render pass using the default store and load actions. You can adjust the descriptor further before using it to create a <doc://com.apple.documentation/documentation/Metal/MTLRenderCommandEncoder>.

Obtain drawables as late as possible; preferably, immediately before encoding your onscreen render pass.

### Registering the Drawable’s Presentation

After rendering the contents, you must present the drawable to update the view’s contents. The most convenient way to present the content is to call the <doc://com.apple.documentation/documentation/Metal/MTLCommandBuffer/present(_:)> method on the command buffer. Then, call the <doc://com.apple.documentation/documentation/Metal/MTLCommandBuffer/commit()> method to submit the command buffer to a GPU:

```swift
if let onscreenDescriptor = view.currentRenderPassDescriptor,
let onscreenCommandEncoder = onscreenCommandBuffer.makeRenderCommandEncoder(descriptor: onscreenDescriptor) {
    /* Set render state and resources.
       ...
     */
    /* Issue draw calls.
       ...
     */
    onscreenCommandEncoder.endEncoding()
    // END encoding your onscreen render pass.

    // Register the drawable's presentation.
    if let currentDrawable = view.currentDrawable {
        onscreenCommandBuffer.present(currentDrawable)
    }
}

// Finalize your onscreen CPU work and commit the command buffer to a GPU.
onscreenCommandBuffer.commit()
```

When a command queue schedules a command buffer for execution, the drawable tracks all render or write requests on itself in that command buffer. The operating system doesn’t present the drawable onscreen until the commands have finished executing. By asking the command buffer to present the drawable, you guarantee that presentation happens after the command queue has scheduled this command buffer. Don’t wait for the command buffer to finish executing before registering the drawable’s presentation.

> Tip:
> For better performance, only retrieve the render pass descriptor when you’re ready to render the contents, and hold onto it and the related drawable object as little as possible. Release it as soon as you finish with it. For more information, see <doc://com.apple.documentation/documentation/QuartzCore/CAMetalLayer#Keeping-References-to-Drawables>.

## Topics

### Creating a View

[`init(coder:)`](/documentation/MetalKit/MTKView/init(coder:))

Initializes a view from data in a given unarchiver.

[`init(frame:device:)`](/documentation/MetalKit/MTKView/init(frame:device:))

Initializes a view with the specified frame rectangle and Metal device.

### Configuring the Delegate

[`delegate`](/documentation/MetalKit/MTKView/delegate)

The view’s delegate.

### Configuring the Metal Device

[`device`](/documentation/MetalKit/MTKView/device)

The device object the view uses to create its Metal objects.

[`preferredDevice`](/documentation/MetalKit/MTKView/preferredDevice)

The device object that the system recommends using for this view.

### Configuring the Color Render Target

[`colorPixelFormat`](/documentation/MetalKit/MTKView/colorPixelFormat)

The color pixel format for the current drawable’s texture.

[`colorspace`](/documentation/MetalKit/MTKView/colorspace)

The color space of the rendered content.

[`framebufferOnly`](/documentation/MetalKit/MTKView/framebufferOnly)

A Boolean value that determines whether the drawable’s textures are used only for rendering.

[`drawableSize`](/documentation/MetalKit/MTKView/drawableSize)

The current size of drawable textures.

[`preferredDrawableSize`](/documentation/MetalKit/MTKView/preferredDrawableSize)

The recommended dimensions of the drawable.

[`autoResizeDrawable`](/documentation/MetalKit/MTKView/autoResizeDrawable)

A Boolean value that controls whether to resize the drawable as the view changes size.

[`clearColor`](/documentation/MetalKit/MTKView/clearColor)

The color to use to clear the color target when creating a render pass descriptor.

### Configuring the Render Target Properties

[`depthStencilPixelFormat`](/documentation/MetalKit/MTKView/depthStencilPixelFormat)

The format used to generate the [`depthStencilTexture`](/documentation/MetalKit/MTKView/depthStencilTexture) object.

[`depthStencilAttachmentTextureUsage`](/documentation/MetalKit/MTKView/depthStencilAttachmentTextureUsage)

The texture usage characteristics that the view uses when creating the depth and stencil textures.

[`clearDepth`](/documentation/MetalKit/MTKView/clearDepth)

The depth value to use to clear the depth target when creating a render pass descriptor.

[`clearStencil`](/documentation/MetalKit/MTKView/clearStencil)

The stencil value to use to clear the stencil target when creating a render pass descriptor.

### Configuring Multisampling

[`sampleCount`](/documentation/MetalKit/MTKView/sampleCount)

The sample count used to generate the [`multisampleColorTexture`](/documentation/MetalKit/MTKView/multisampleColorTexture) object.

[`multisampleColorAttachmentTextureUsage`](/documentation/MetalKit/MTKView/multisampleColorAttachmentTextureUsage)

The texture usage characteristics that the view uses when creating multisample textures.

### Retrieving Render Target Information

[`currentRenderPassDescriptor`](/documentation/MetalKit/MTKView/currentRenderPassDescriptor)

A render pass descriptor to draw into the current drawable.

[`currentDrawable`](/documentation/MetalKit/MTKView/currentDrawable)

The drawable to use for the current frame.

[`depthStencilTexture`](/documentation/MetalKit/MTKView/depthStencilTexture)

A packed depth and stencil texture associated with the current drawable object’s texture.

[`depthStencilStorageMode`](/documentation/MetalKit/MTKView/depthStencilStorageMode)

The storage mode that the packed depth and stencil texture use.

[`multisampleColorTexture`](/documentation/MetalKit/MTKView/multisampleColorTexture)

The multisample color sample texture to render into.

### Configuring Drawing Behavior

[`preferredFramesPerSecond`](/documentation/MetalKit/MTKView/preferredFramesPerSecond)

The rate at which the view redraws its contents.

[`isPaused`](/documentation/MetalKit/MTKView/isPaused)

A Boolean value that indicates whether the draw loop is paused.

[`enableSetNeedsDisplay`](/documentation/MetalKit/MTKView/enableSetNeedsDisplay)

A Boolean value that indicates whether the view responds to <doc://com.apple.documentation/documentation/UIKit/UIView/setNeedsDisplay()>.

[`draw()`](/documentation/MetalKit/MTKView/draw())

Redraws the view’s contents immediately.

[`presentsWithTransaction`](/documentation/MetalKit/MTKView/presentsWithTransaction)

A Boolean value that determines whether the view presents its content using a Core Animation transaction.

### Releasing Memory

[`releaseDrawables()`](/documentation/MetalKit/MTKView/releaseDrawables())

Releases the [`depthStencilTexture`](/documentation/MetalKit/MTKView/depthStencilTexture) and [`multisampleColorTexture`](/documentation/MetalKit/MTKView/multisampleColorTexture) objects.



---

Copyright &copy; 2026 Apple Inc. All rights reserved. | [Terms of Use](https://www.apple.com/legal/internet-services/terms/site.html) | [Privacy Policy](https://www.apple.com/privacy/privacy-policy)
