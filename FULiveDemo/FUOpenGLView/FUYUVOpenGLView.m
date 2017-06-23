//
//  FUYUVOpenGLView.m
//  FULiveDemo
//
//  Created by 千山暮雪 on 2017/6/19.
//  Copyright © 2017年 刘洋. All rights reserved.
//

#import "FUYUVOpenGLView.h"
#import <GLKit/GLKit.h>
#import <SVProgressHUD/SVProgressHUD.h>

// 设置拍照和录像功能
typedef enum : NSUInteger {
    CommonMode,
    PhotoTakeMode,
    PhotoTakeAndSaveMode,
    VideoRecordMode,
} RunMode;

// Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    NUM_ATTRIBUTES
};

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
    1.164,  1.164, 1.164,
		  0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
    1.164,  1.164, 1.164,
		  0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
const GLfloat kColorConversion601FullRange[] = {
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
};

@interface FUYUVOpenGLView ()
{
    // layer 的像素
    GLint _backingWidth ;
    GLint _backingHeight ;
    
    EAGLContext *_context ;
    CVOpenGLESTextureRef _lumatexture ;// 亮度
    CVOpenGLESTextureRef _chromatexture ;//色彩
    CVOpenGLESTextureCacheRef _videoTextureCache ;//缓存
    
    GLuint _frameBufferHandle ;
    GLuint _colorBufferHandle ;
    
    const GLfloat *_preferredConversion ;
    
    RunMode runMode ;
}

@property (nonatomic, assign) GLuint program ;

- (void)setupBuffers ;

- (void)cleanUpTextures ;

- (BOOL)loadShaders ;

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)url ;

- (BOOL)linkProgram:(GLuint)prog;

- (BOOL)validateProgram:(GLuint)prog;

@end

@implementation FUYUVOpenGLView

+(Class)layerClass {
    return [CAEAGLLayer class];
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.contentScaleFactor = [[UIScreen mainScreen] scale];
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        eaglLayer.opaque = TRUE;
        eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
                                          kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!_context || ![EAGLContext setCurrentContext:_context] || ![self loadShaders]) {
            return nil;
        }
        _preferredConversion = kColorConversion709;
        [self setupGL];
        
        runMode = CommonMode ;
    }
    return self ;
}

-(instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentScaleFactor = [[UIScreen mainScreen] scale];
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        eaglLayer.opaque = TRUE;
        eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
                                          kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!_context || ![EAGLContext setCurrentContext:_context] || ![self loadShaders]) {
            return nil;
        }
        _preferredConversion = kColorConversion709;
        [self setupGL];
        
        runMode = CommonMode ;
    }
    return self;
}

#pragma mark -- shader compilation

-(BOOL)loadShaders {
    
    GLuint vertShader, fragShader ;
    NSURL *vertShaderURL, *fragShaderURL;
    
    self.program = glCreateProgram() ;
    
    vertShaderURL = [[NSBundle mainBundle] URLForResource:@"YUVShader" withExtension:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER URL:vertShaderURL]) {
        NSLog(@"----- failed to compile vertex shader ~");
        return NO ;
    }
    
    fragShaderURL = [[NSBundle mainBundle] URLForResource:@"YUVShader" withExtension:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER URL:fragShaderURL]) {
        NSLog(@"----- fail to compile fragment shader");
        return NO ;
    }
    
    glAttachShader(self.program, vertShader) ;
    glAttachShader(self.program, fragShader) ;
    
    glBindAttribLocation(self.program, ATTRIB_VERTEX, "position") ;
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
    
    if (![self linkProgram:self.program]) {
        NSLog(@"----- fail to link program : %d",self.program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0 ;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0 ;
        }
        if (self.program) {
            glDeleteProgram(self.program);
            self.program = 0 ;
        }
        return NO ;
    }
    
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    
    // Release
    if (vertShader) {
        glDetachShader(self.program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(self.program, fragShader);
        glDeleteShader(fragShader);
    }
    return YES;
}

-(BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)url {
    
    NSError *error ;
    NSString *souceString = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    if (souceString == nil) {
        NSLog(@"----- fail to load vertex shader :%@",[error localizedDescription]);
        return NO ;
    }
    
    GLint status ;
    const GLchar *source ;
    source = (GLchar *)souceString.UTF8String ;
    
    *shader = glCreateShader(type) ;
    glShaderSource(*shader, 1, &source, NULL) ;
    glCompileShader(*shader) ;
    
#if defined(DEBUG)
    GLint logLength ;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength) ;
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength) ;
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"----- shader compile log :%s",log);
        free(log) ;
    }
#endif
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO ;
    }
    
    return YES ;
}

-(void)setupGL {
    
    [EAGLContext setCurrentContext:_context];
    [self setupBuffers];
    [self loadShaders];
    
    glUseProgram(self.program) ;
    
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
}

-(void)setupBuffers {
    
    glDisable(GL_DEPTH_TEST);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glGenFramebuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"----- Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

-(BOOL)linkProgram:(GLuint)prog {
    
    GLint status ;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    
    GLint logLength ;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"----- program link log : %s",log);
        free(log);
    }
#endif
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0 ) {
        return  NO ;
    }
    return YES ;
}

-(BOOL)validateProgram:(GLuint)prog {
    
    GLint logLength, status ;
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    
    if (logLength > 0 ) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"--- program validate log : %s",log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0 ) {
        return  NO ;
    }
    return YES ;
}

-(void)cleanUpTextures {
    
    if (_lumatexture) {
        CFRelease(_lumatexture);
        _lumatexture = nil ;
    }
    
    if (_chromatexture) {
        CFRelease(_chromatexture);
        _chromatexture = nil ;
    }
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}

-(void)dealloc {
    [self cleanUpTextures];
    if (_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
}

#pragma mark ---OpenGL Drawing - 开始绘图

-(void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    
    if (!pixelBuffer) {
        return ;
    }
    
    CVReturn err ;
    int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
    int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    if (!_videoTextureCache) {
        NSLog(@"----- No video texture cache ~");
        return ;
    }
    
    if ([EAGLContext currentContext] != _context) {
        [EAGLContext setCurrentContext:_context];
    }
    
    [self cleanUpTextures];
    
    //
    CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
        if (self.isFullYUVRange) {
            _preferredConversion = kColorConversion601FullRange ;
        }else {
            _preferredConversion = kColorConversion601 ;
        }
    }else {
        _preferredConversion = kColorConversion709 ;
    }
    
    glActiveTexture(GL_TEXTURE0);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_LUMINANCE,
                                                       frameWidth,
                                                       frameHeight,
                                                       GL_LUMINANCE,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &_lumatexture) ;
    
    if (err) {
        NSLog(@"----- error at CVOpenGLESTextureCacheCreateTextureFromImage %d",err);
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_lumatexture), CVOpenGLESTextureGetName(_lumatexture)) ;
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glActiveTexture(GL_TEXTURE1);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_LUMINANCE_ALPHA,
                                                       frameWidth / 2,
                                                       frameHeight / 2,
                                                       GL_LUMINANCE_ALPHA,
                                                       GL_UNSIGNED_BYTE,
                                                       1,
                                                       &_chromatexture);
    
    if (err) {
        NSLog(@"----- error at CVOpenGLESTextureCacheCreateTextureFromImage %d",err);
    }
    glBindTexture(CVOpenGLESTextureGetTarget(_chromatexture), CVOpenGLESTextureGetName(_chromatexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    
    glClearColor(0.1, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glUseProgram(self.program);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    //    CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(_backingWidth, _backingHeight), self.layer.bounds);
    
    CGSize normalizedSamplingSuze = CGSizeMake(0, 0);
    //    CGSize cropScaleAmount = CGSizeMake(self.layer.bounds.size.width / 480.0 ,self.layer.bounds.size.height/640.0) ;
    CGSize cropScaleAmount = CGSizeMake(self.layer.bounds.size.width / frameWidth ,self.layer.bounds.size.height/ frameHeight) ;
    
    if (cropScaleAmount.width > cropScaleAmount.height) {
        normalizedSamplingSuze.height = cropScaleAmount.width / cropScaleAmount.height ;
        normalizedSamplingSuze.width = 1.0 ;
    }else {
        normalizedSamplingSuze.width = cropScaleAmount.height / cropScaleAmount.width ;
        normalizedSamplingSuze.height = 1.0 ;
    }
    
    GLfloat quadVertexData [] = {
        -1 * normalizedSamplingSuze.width, -1 * normalizedSamplingSuze.height,
        1 * normalizedSamplingSuze.width, -1 * normalizedSamplingSuze.height,
        -1 * normalizedSamplingSuze.width,  1 * normalizedSamplingSuze.height,
        1 * normalizedSamplingSuze.width,  1 * normalizedSamplingSuze.height
    };
    
    // 更新顶点数据
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    GLfloat quadTextureData[] =  {
        0, 1,
        1, 1,
        0, 0,
        1, 0,
    };
    
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    if ([EAGLContext currentContext] == _context) {
        [_context presentRenderbuffer:GL_RENDERBUFFER];
    }
    
    switch (runMode) {
        case CommonMode:
            break;
        case PhotoTakeAndSaveMode: {// 拍照并且保存
            runMode = CommonMode ;
            UIImage *image = [self imageFromPixelBuffer:pixelBuffer isFront:NO];
            if (image) {
                UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
            }
        }
            break;
            
        default:
            break;
    }
}

- (void)takePhotoAndSave {
    runMode = PhotoTakeAndSaveMode ;
}

- (UIImage *)imageFromPixelBuffer:(CVPixelBufferRef)pixelBufferRef isFront:(BOOL) isFront{
    
    CVPixelBufferLockBaseAddress(pixelBufferRef, 0);
    
    CGFloat SW = [UIScreen mainScreen].bounds.size.width;
    CGFloat SH = [UIScreen mainScreen].bounds.size.height;
    
    float width = CVPixelBufferGetWidth(pixelBufferRef);
    float height = CVPixelBufferGetHeight(pixelBufferRef);
    
    float dw = width / SW;
    float dh = height / SH;
    
    float cropW = width;
    float cropH = height;
    
    if (dw > dh) {
        cropW = SW * dh;
    }else
    {
        cropH = SH * dw;
    }
    
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBufferRef];
    
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext createCGImage:ciImage fromRect:CGRectMake(0, 0, width, height)];
    
    UIImage *image ;
    if (isFront) {
        image = [UIImage imageWithCGImage:videoImage scale:1.0 orientation:UIImageOrientationUpMirrored];
    }else {
        image = [UIImage imageWithCGImage:videoImage];
    }
    
    CGImageRelease(videoImage);
    CVPixelBufferUnlockBaseAddress(pixelBufferRef, 0);
    
    return image;
}

- (void)image: (UIImage *) image didFinishSavingWithError: (NSError *) error contextInfo: (void *) contextInfo
{
    //    [SVProgressHUD setMaximumDismissTimeInterval:1.5];
    [SVProgressHUD setMinimumDismissTimeInterval:1.5];
    if(error != NULL){
        [SVProgressHUD showErrorWithStatus:@"图片保存失败"];
    }else{
        [SVProgressHUD showSuccessWithStatus:@"图片保存成功"];
    }
}
@end
