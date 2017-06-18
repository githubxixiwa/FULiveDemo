//
//  ViewController.m
//  FUAPIDemo
//
//  Created by 刘洋 on 2017/1/9.
//  Copyright © 2017年 刘洋. All rights reserved.
//

#import "ViewController.h"
#import <GLKit/GLKit.h>
#import "FUCamera.h"
#import <FUAPIDemoBar/FUAPIDemoBar.h>

#import "FURenderer.h"
#include <sys/mman.h>
#include <sys/stat.h>
#import "authpack.h"

#import "FUVideoFrame.h"
#import "FUOpenGLView.h"

@interface ViewController ()<FUAPIDemoBarDelegate,FUCameraDelegate>
{
    //MARK: Faceunity
    int items[3];
    int frameID;
    
    struct FUVideoFrame inFrame ;
    struct FUVideoFrame outFrame;
    
    CVPixelBufferRef pixelBuffer ;
    
    // --------------- Faceunity ----------------
    
    FUCamera *curCamera;
}
@property (weak, nonatomic) IBOutlet FUAPIDemoBar *demoBar;//工具条

@property (nonatomic, strong) FUCamera *bgraCamera;//BGRA摄像头

@property (nonatomic, strong) FUCamera *yuvCamera;//YUV摄像头

@property (weak, nonatomic) IBOutlet UILabel *noTrackView;

@property (weak, nonatomic) IBOutlet UIButton *photoBtn;

@property (weak, nonatomic) IBOutlet UIButton *barBtn;

@property (weak, nonatomic) IBOutlet UISegmentedControl *segment;

@property (weak, nonatomic) IBOutlet UIButton *changeCameraBtn;

@property (strong, nonatomic) IBOutlet FUOpenGLView *bgraGLView;

// 输出队列
@property (nonatomic, copy) dispatch_queue_t outputQueue;
// 信号量
@property (nonatomic, strong)dispatch_semaphore_t bufferSemaphore ;
@end

@implementation ViewController

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _outputQueue = dispatch_queue_create("output.FaceUnity", DISPATCH_QUEUE_SERIAL);
    _bufferSemaphore = dispatch_semaphore_create(1);
    
    [self addObserver];
    
    [self initFaceunity];
    
    curCamera = self.bgraCamera;
    [curCamera startUp];
    
}

- (void)initFaceunity
{
    #warning faceunity全局只需要初始化一次
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int size = 0;
        void *v3 = [self mmap_bundle:@"v3.bundle" psize:&size];
        
        [[FURenderer shareRenderer] setupWithData:v3 ardata:NULL authPackage:&g_auth_package authSize:sizeof(g_auth_package)];
    });
    
    //开启多脸识别（最高可设为8，不过考虑到性能问题建议设为4以内）
//    fuSetMaxFaces(4);
    
    [self loadItem];
    [self loadFilter];
}

- (void)destoryFaceunityItems
{
    [self setUpContext];
    
    fuDestroyAllItems();
    
    for (int i = 0; i < sizeof(items) / sizeof(int); i++) {
        items[i] = 0;
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self destoryFaceunityItems];
}

- (void)addObserver{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

//底部工具条
- (void)setDemoBar:(FUAPIDemoBar *)demoBar
{
    _demoBar = demoBar;
    _demoBar.itemsDataSource = @[@"noitem", @"tiara", @"item0208", @"YellowEar", @"PrincessCrown", @"Mood" , @"Deer" , @"BeagleDog", @"item0501", @"item0210",  @"HappyRabbi", @"item0204", @"hartshorn", @"ColorCrown"];
    _demoBar.selectedItem = _demoBar.itemsDataSource[1];

    _demoBar.filtersDataSource = @[@"nature", @"delta", @"electric", @"slowlived", @"tokyo", @"warm"];
    _demoBar.selectedFilter = _demoBar.filtersDataSource[0];

    _demoBar.selectedBlur = 6;

    _demoBar.beautyLevel = 0.2;
    
    _demoBar.thinningLevel = 1.0;
    
    _demoBar.enlargingLevel = 0.5;
    
    _demoBar.faceShapeLevel = 0.5;
    
    _demoBar.faceShape = 3;
    
    _demoBar.redLevel = 0.5;

    _demoBar.delegate = self;
}

//bgra摄像头
- (FUCamera *)bgraCamera
{
    if (!_bgraCamera) {
        _bgraCamera = [[FUCamera alloc] init];
        
        _bgraCamera.delegate = self;
        
    }
    
    return _bgraCamera;
}

//yuv摄像头
- (FUCamera *)yuvCamera
{
    if (!_yuvCamera) {
        _yuvCamera = [[FUCamera alloc] initWithCameraPosition:AVCaptureDevicePositionFront captureFormat:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
        
        _yuvCamera.delegate = self;
    }
    
    return _yuvCamera;
}

- (void)willResignActive
{
    
    [curCamera stopCapture];
    
}

- (void)willEnterForeground
{
    
    [curCamera startCapture];
}

- (void)didBecomeActive
{
    static BOOL firstActive = YES;
    if (firstActive) {
        firstActive = NO;
        return;
    }
    [curCamera startCapture];
}

//拍照
- (IBAction)takePhoto
{
    //拍照效果
    self.photoBtn.enabled = NO;
    UIView *whiteView = [[UIView alloc] initWithFrame:self.view.bounds];
    whiteView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:whiteView];
    whiteView.alpha = 0.3;
    [UIView animateWithDuration:0.1 animations:^{
        whiteView.alpha = 0.8;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            whiteView.alpha = 0;
        } completion:^(BOOL finished) {
            self.photoBtn.enabled = YES;
            [whiteView removeFromSuperview];
        }];
    }];
//    
//    [curCamera takePhotoAndSave];
    
    [self.bgraGLView takePhotoAndSave];
}

#pragma -显示工具栏
- (IBAction)filterBtnClick:(UIButton *)sender {
    self.barBtn.hidden = YES;
    self.photoBtn.hidden = YES;
    
    [UIView animateWithDuration:0.5 animations:^{
        self.demoBar.transform = CGAffineTransformMakeTranslation(0, -self.demoBar.frame.size.height);
    }];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches allObjects].firstObject;
    if (touch.view != self.view) {
        return;
    }
    [UIView animateWithDuration:0.5 animations:^{
        self.demoBar.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.barBtn.hidden = NO;
        self.photoBtn.hidden = NO;
    }];
}

#pragma -摄像头切换
- (IBAction)changeCamera:(UIButton *)sender {
    
    [self.bgraCamera changeCameraInputDeviceisFront:!self.bgraCamera.isFrontCamera];
    [self.yuvCamera changeCameraInputDeviceisFront:!self.yuvCamera.isFrontCamera];
    [curCamera startCapture];
    
#warning 切换摄像头要调用此函数
    fuOnCameraChange();
}

#pragma -BGRA/YUV切换
- (IBAction)changeCaptureFormat:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0 && curCamera == self.yuvCamera)
    {
        [curCamera stopCapture];
        curCamera = self.bgraCamera;
    }else if (sender.selectedSegmentIndex == 1 && curCamera == self.bgraCamera){
        [curCamera stopCapture];
        curCamera = self.yuvCamera;
    }
    [curCamera startCapture];
    
}

#pragma -FUAPIDemoBarDelegate
- (void)demoBarDidSelectedItem:(NSString *)item
{
    //异步加载道具
    [self loadItem];
}

#pragma -FUCameraDelegate
- (void)didOutputVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return;
    }
    
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sampleBuffer) ;
    CVPixelBufferLockBaseAddress(buffer, 0);
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t size = CVPixelBufferGetDataSize(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    uint8_t *bufferImage = CVPixelBufferGetBaseAddress(buffer) ;
    
    if (inFrame.width != width || inFrame.height != height) {
        free(inFrame.bgraImg);
        inFrame.bgraImg = malloc(size * sizeof(void));
    }
    inFrame.width = width ;
    inFrame.height = height ;
    inFrame.size = size ;
    inFrame.stride = stride ;
    inFrame.isUsed = NO ;
    memcpy(inFrame.bgraImg, bufferImage, size);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    
    if (dispatch_semaphore_wait(_bufferSemaphore, DISPATCH_TIME_NOW) != 0) {
//        NSLog(@"********* 进入~");
        return;
    }
    
    dispatch_async(_outputQueue, ^{
        
        if (outFrame.width != inFrame.width || outFrame.height != inFrame.height) {
            free(outFrame.bgraImg) ;
            outFrame.bgraImg = malloc(size * sizeof(void)) ;
        }
        outFrame.width = inFrame.width ;
        outFrame.height = inFrame.height ;
        outFrame.size = inFrame.size ;
        outFrame.stride = inFrame.stride ;
        memcpy(outFrame.bgraImg, inFrame.bgraImg, size) ;
        //        inFrame.isUsed = YES ;
        [self outframCopyCompleted];
        
        dispatch_semaphore_signal(_bufferSemaphore);
    });
}

- (void)outframCopyCompleted {
    
    while (!inFrame.isUsed) {
//        NSLog(@"------------------------- 循环输出~ ");
        outFrame.width = inFrame.width ;
        outFrame.height = inFrame.height ;
        outFrame.size = inFrame.size ;
        outFrame.stride = inFrame.stride ;
        memcpy(outFrame.bgraImg, inFrame.bgraImg, inFrame.size);
        //        inFrame.isUsed = YES ;
        
        [self getPixelbufferWithOutVideoFrame];
    }
}

- (void)getPixelbufferWithOutVideoFrame {
    
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    if (!pixelBuffer || width != outFrame.width || height != outFrame.height ) {
        [self createPixelBufferWithSize:CGSizeMake(outFrame.width, outFrame.height)];
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    uint8_t *bufferImg = CVPixelBufferGetBaseAddress(pixelBuffer);
    memcpy(bufferImg, outFrame.bgraImg, outFrame.size);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    [self setUpContext];
    
    fuItemSetParamd(items[1], "cheek_thinning", 1.0); //瘦脸
    fuItemSetParamd(items[1], "eye_enlarging", 0.5); //大眼
    fuItemSetParamd(items[1], "color_level", 0.2); //美白
    fuItemSetParams(items[1], "filter_name", (char *)[@"nature" UTF8String]); //滤镜
    fuItemSetParamd(items[1], "blur_level", 6); //磨皮
    fuItemSetParamd(items[1], "face_shape", 3); //瘦脸类型
    fuItemSetParamd(items[1], "face_shape_level", 0.5); //瘦脸等级
    fuItemSetParamd(items[1], "red_level", 0.5); //红润
    
    [[FURenderer shareRenderer] renderPixelBuffer:pixelBuffer withFrameId:frameID items:items itemCount:3 flipx:YES];
    frameID += 1;
    
    [self.bgraGLView displayPixelBuffer:pixelBuffer IsMirror:NO];
}

- (void)createPixelBufferWithSize:(CGSize)size {
    if (pixelBuffer) {
        CFRelease(pixelBuffer) ;
        pixelBuffer = nil ;
    }
    NSDictionary* pixelBufferOptions = @{ (NSString*) kCVPixelBufferPixelFormatTypeKey :
                                              @(kCVPixelFormatType_32BGRA),
                                          (NSString*) kCVPixelBufferWidthKey : @(size.width),
                                          (NSString*) kCVPixelBufferHeightKey : @(size.height),
                                          (NSString*) kCVPixelBufferOpenGLESCompatibilityKey : @YES,
                                          (NSString*) kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVPixelBufferCreate(kCFAllocatorDefault,
                        size.width, size.height,
                        kCVPixelFormatType_32BGRA,
                        (__bridge CFDictionaryRef)pixelBufferOptions,
                        &pixelBuffer);
}

#pragma -Faceunity Set EAGLContext
static EAGLContext *mcontext;

- (void)setUpContext
{
    if(!mcontext){
        mcontext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    if(!mcontext || ![EAGLContext setCurrentContext:mcontext]){
        NSLog(@"faceunity: failed to create / set a GLES2 context");
    }
    
}

#pragma -Faceunity Load Data
- (void)loadItem
{
    [self setUpContext];
    
    if ([_demoBar.selectedItem isEqual: @"noitem"] || _demoBar.selectedItem == nil)
    {
        if (items[0] != 0) {
            NSLog(@"faceunity: destroy item");
            fuDestroyItem(items[0]);
        }
        items[0] = 0;
        return;
    }
    
    int size = 0;
    
    // 先创建再释放可以有效缓解切换道具卡顿问题
    void *data = [self mmap_bundle:[_demoBar.selectedItem stringByAppendingString:@".bundle"] psize:&size];
    
    int itemHandle = fuCreateItemFromPackage(data, size);
    
    if (items[0] != 0) {
        NSLog(@"faceunity: destroy item");
        fuDestroyItem(items[0]);
    }
    
    items[0] = itemHandle;
    
    NSLog(@"faceunity: load item");
}

- (void)loadFilter
{
    [self setUpContext];
    
    int size = 0;
    
    void *data = [self mmap_bundle:@"face_beautification.bundle" psize:&size];
    
    items[1] = fuCreateItemFromPackage(data, size);
}

- (void)loadHeart
{
    [self setUpContext];
    
    int size = 0;
    
    void *data = [self mmap_bundle:@"heart_v2.bundle" psize:&size];
    
    items[2] = fuCreateItemFromPackage(data, size);
}

- (void *)mmap_bundle:(NSString *)bundle psize:(int *)psize {
    
    // Load item from predefined item bundle
    NSString *str = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:bundle];
    const char *fn = [str UTF8String];
    int fd = open(fn,O_RDONLY);
    
    int size = 0;
    void* zip = NULL;
    
    if (fd == -1) {
        NSLog(@"faceunity: failed to open bundle");
        size = 0;
    }else
    {
        size = [self getFileSize:fd];
        zip = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0);
    }
    
    *psize = size;
    return zip;
}

- (int)getFileSize:(int)fd
{
    struct stat sb;
    sb.st_size = 0;
    fstat(fd, &sb);
    return (int)sb.st_size;
}

@end

