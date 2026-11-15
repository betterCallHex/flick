import AppKit
import CMpv
import OpenGL.GL3
import Synchronization

final class VideoLayer: CAOpenGLLayer {
    var onFirstFrame: (() -> Void)?
    private let mpv: Mpv
    private let pixelFormat: CGLPixelFormatObj
    private let glContext: CGLContextObj
    private let renderContext: OpaquePointer
    private let ownsRenderContext: Bool
    private let needsDraw = Atomic<Bool>(false)
    private var hasDrawnFrame = false

    init(mpv: Mpv) throws {
        self.mpv = mpv
        pixelFormat = try Self.makePixelFormat()
        glContext = try Self.makeContext(pixelFormat)
        renderContext = try Self.makeRenderContext(mpv: mpv, glContext: glContext)
        ownsRenderContext = true
        super.init()
        isOpaque = true
        isAsynchronous = true
        backgroundColor = NSColor.black.cgColor
        mpv_render_context_set_update_callback(renderContext, { context in
            Unmanaged<VideoLayer>.fromOpaque(context!).takeUnretainedValue().requestDraw()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    override init(layer: Any) {
        let source = layer as! VideoLayer
        mpv = source.mpv
        pixelFormat = source.pixelFormat
        glContext = source.glContext
        renderContext = source.renderContext
        ownsRenderContext = false
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("VideoLayer is created in code only")
    }

    deinit {
        guard ownsRenderContext else { return }
        CGLSetCurrentContext(glContext)
        mpv_render_context_free(renderContext)
        CGLSetCurrentContext(nil)
    }

    func requestDraw() {
        needsDraw.store(true, ordering: .relaxed)
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        CGLRetainPixelFormat(pixelFormat)
    }

    override func copyCGLContext(forPixelFormat pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        CGLRetainContext(glContext)
    }

    override func canDraw(
        inCGLContext context: CGLContextObj,
        pixelFormat: CGLPixelFormatObj,
        forLayerTime layerTime: CFTimeInterval,
        displayTime: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        needsDraw.load(ordering: .relaxed)
    }

    override func draw(
        inCGLContext context: CGLContextObj,
        pixelFormat: CGLPixelFormatObj,
        forLayerTime layerTime: CFTimeInterval,
        displayTime: UnsafePointer<CVTimeStamp>?
    ) {
        needsDraw.store(false, ordering: .relaxed)
        let updateFlags = mpv_render_context_update(renderContext)
        render()
        glFlush()
        guard updateFlags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0, !hasDrawnFrame else { return }
        hasDrawnFrame = true
        onFirstFrame?()
    }

    private func render() {
        var framebuffer: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &framebuffer)
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        var target = mpv_opengl_fbo(fbo: Int32(framebuffer), w: viewport[2], h: viewport[3], internal_format: 0)
        var flipY: Int32 = 1
        withUnsafeMutablePointer(to: &target) { targetPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var parameters = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: targetPointer),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPointer),
                    mpv_render_param(),
                ]
                mpv_render_context_render(renderContext, &parameters)
            }
        }
    }

    private static func makePixelFormat() throws -> CGLPixelFormatObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var formatCount: GLint = 0
        CGLChoosePixelFormat(attributes, &pixelFormat, &formatCount)
        guard let pixelFormat else { throw VideoLayerError.noPixelFormat }
        return pixelFormat
    }

    private static func makeContext(_ pixelFormat: CGLPixelFormatObj) throws -> CGLContextObj {
        var context: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &context)
        guard let context else { throw VideoLayerError.noContext }
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)
        CGLEnable(context, kCGLCEMPEngine)
        return context
    }

    private static func makeRenderContext(mpv: Mpv, glContext: CGLContextObj) throws -> OpaquePointer {
        CGLSetCurrentContext(glContext)
        defer { CGLSetCurrentContext(nil) }
        var initParameters = mpv_opengl_init_params(get_proc_address: openGLProcAddress, get_proc_address_ctx: nil)
        let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)
        defer { free(apiType) }
        var renderContext: OpaquePointer?
        let status = withUnsafeMutablePointer(to: &initParameters) { initPointer in
            var parameters = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initPointer),
                mpv_render_param(),
            ]
            return mpv_render_context_create(&renderContext, mpv.handle, &parameters)
        }
        guard status >= 0, let renderContext else { throw MpvError(code: status) }
        return renderContext
    }
}

enum VideoLayerError: Error {
    case noPixelFormat
    case noContext
}

private func openGLProcAddress(_ context: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    let openGL = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
    return CFBundleGetFunctionPointerForName(openGL, symbol)
}
