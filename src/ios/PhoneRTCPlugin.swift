import Foundation
import AVFoundation

@objc(PhoneRTCPlugin)
class PhoneRTCPlugin : CDVPlugin {
    var sessions: [String: Session]!
    var peerConnectionFactory: RTCPeerConnectionFactory!
    
    var videoConfig: VideoConfig?
    var videoCapturer: RTCVideoCapturer?
    var videoSource: RTCVideoSource?
    var localVideoView: RTCEAGLVideoView?
    var remoteVideoViews: [VideoTrackViewPair]!
    var camera: String?
    
    var localVideoTrack: RTCVideoTrack?
    var localAudioTrack: RTCAudioTrack?
    
    override func pluginInitialize() {
        self.sessions = [:];
        self.remoteVideoViews = [];
        
        peerConnectionFactory = RTCPeerConnectionFactory()
        RTCPeerConnectionFactory.initializeSSL()
    }
    
    func createSessionObject(_ command: CDVInvokedUrlCommand) {
        if let sessionKey = command.argument(at: 0) as? String {
            // create a session and initialize it.
            if let args = command.argument(at: 1) as? [String:Any] {
                let config = SessionConfig(data: args)
                let session = Session(plugin: self, peerConnectionFactory: peerConnectionFactory,
                                      config: config, callbackId: command.callbackId,
                                      sessionKey: sessionKey)
                sessions[sessionKey] = session
            }
        }
    }
    
    func call(_ command: CDVInvokedUrlCommand) {
        let args = command.argument(at: 0) as! [String:Any]
        if let sessionKey = args["sessionKey"] as? String {
            DispatchQueue.main.async {
                if let session = self.sessions[sessionKey] {
                    session.call()
                }
            }
        }
    }
    
    func receiveMessage(_ command: CDVInvokedUrlCommand) {
        let args = command.argument(at: 0) as! [String:Any]
        if let sessionKey = args["sessionKey"] as? String {
            if let message = args["message"] as? String {
                if let session = self.sessions[sessionKey] {
                    DispatchQueue.global().async() {
                        session.receiveMessage(message: message)
                    }
                }
            }
        }
    }
    
    func renegotiate(_ command: CDVInvokedUrlCommand) {
        let args = command.argument(at: 0) as! [String:Any]
        if let sessionKey = args["sessionKey"] as? String {
            if let config = args["config"] {
                DispatchQueue.main.async {
                    if let session = self.sessions[sessionKey] {
                        session.config = SessionConfig(data: config as! [String : Any])
                        session.createOrUpdateStream()
                    }
                }
            }
        }
    }
    
    func disconnect(_ command: CDVInvokedUrlCommand) {
        let args = command.argument(at: 0) as! [String:Any]
        if let sessionKey = args["sessionKey"] as? String {
            DispatchQueue.global().async() {
                if (self.sessions[sessionKey] != nil) {
                    self.sessions[sessionKey]!.disconnect(sendByeMessage: true)
                }
            }
        }
    }
    
    func sendMessage(callbackId: String, message: Data) {
        let json = (try! JSONSerialization.jsonObject(with: message,
                                                      options: JSONSerialization.ReadingOptions.mutableLeaves)) as! NSDictionary
        
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: json as [NSObject : AnyObject])
        pluginResult?.setKeepCallbackAs(true);
        
        self.commandDelegate!.send(pluginResult, callbackId:callbackId)
    }
    
    func setVideoView(_ command: CDVInvokedUrlCommand) {
        let config = command.argument(at: 0) as! [String:Any]
        
        DispatchQueue.main.async {
         // create session config from the JS params
        let videoConfig = VideoConfig(data: config)
         
         // make sure that it's not junk
         if videoConfig.container.width == 0 || videoConfig.container.height == 0 {
         return
         }
         
         self.videoConfig = videoConfig
         
         // get cameraParams from the JS params
         self.camera = config["camera"] as? String
         
         // add local video view
         if self.videoConfig!.local != nil {
            if self.localVideoTrack == nil {
                if(self.camera == "Front" || self.camera == "Back") {
                    self.initLocalVideoTrack(camera: self.camera!)
                }else {
                    self.initLocalVideoTrack()
                }
            }
         
            if self.videoConfig!.local == nil {
         // remove the local video view if it exists and
         // the new config doesn't have the `local` property
                if self.localVideoView != nil {
                    self.localVideoView!.isHidden = true
                    self.localVideoView!.removeFromSuperview()
                    self.localVideoView = nil
                }
            } else {
                let params = self.videoConfig!.local!
         
         // if the local video view already exists, just
         // change its position according to the new config.
                if self.localVideoView != nil {
                    self.localVideoView!.frame = CGRect(x: CGFloat(params.x + self.videoConfig!.container.x), y: CGFloat(params.y + self.videoConfig!.container.y), width: CGFloat(params.width), height: CGFloat(params.height))
                } else {
         // otherwise, create the local video view
                    self.localVideoView = self.createVideoView(params: params)
                    self.localVideoTrack!.add(self.localVideoView!)
                }
            }
            self.refreshVideoContainer()
        }
        }
    }
    
    func hideVideoView(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            if (self.localVideoView != nil) {
                self.localVideoView!.isHidden = true;
            }
            for remoteVideoView in self.remoteVideoViews {
                remoteVideoView.videoView.isHidden = true;
            }
        }
    }
    
    func showVideoView(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            if (self.localVideoView != nil) {
                self.localVideoView!.isHidden = false;
            }
            for remoteVideoView in self.remoteVideoViews {
                remoteVideoView.videoView.isHidden = false;
            }
        }
    }
    
    func createVideoView(params: VideoLayoutParams? = nil) -> RTCEAGLVideoView {
        var view: RTCEAGLVideoView
        
        if params != nil {
            let frame = CGRect(x: CGFloat(params!.x + self.videoConfig!.container.x), y: CGFloat(params!.y + self.videoConfig!.container.y), width: CGFloat(params!.width), height: CGFloat(params!.height))
            
            view = RTCEAGLVideoView(frame: frame)
        } else {
            view = RTCEAGLVideoView()
        }
        
        view.isUserInteractionEnabled = false
        
        self.webView!.addSubview(view)
        self.webView!.bringSubview(toFront: view)
        
        return view
    }
    
    func initLocalAudioTrack() {
        localAudioTrack = peerConnectionFactory.audioTrack(withID: "ARDAMSa0")
    }
    
    func initLocalVideoTrack() {
        var cameraID: String?
        for captureDevice in AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) {
            // TODO: Make this camera option configurable
            if (captureDevice as AnyObject).position == AVCaptureDevicePosition.front {
                cameraID = (captureDevice as AnyObject).localizedName
            }
        }
        
        self.videoCapturer = RTCVideoCapturer(deviceName: cameraID)
        self.videoSource = self.peerConnectionFactory.videoSource(
            with: self.videoCapturer,
            constraints: RTCMediaConstraints()
        )
        
        self.localVideoTrack = self.peerConnectionFactory
            .videoTrack(withID: "ARDAMSv0", source: self.videoSource)
    }
    
    func initLocalVideoTrack(camera: String) {
        NSLog("PhoneRTC: initLocalVideoTrack(camera: String) invoked")
        var cameraID: String?
        for captureDevice in AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) {
            // TODO: Make this camera option configurable
            if (captureDevice as AnyObject).position == AVCaptureDevicePosition.front {
                if camera == "Front"{
                    cameraID = (captureDevice as AnyObject).localizedName
                }
            }
            if (captureDevice as AnyObject).position == AVCaptureDevicePosition.back {
                if camera == "Back"{
                    cameraID = (captureDevice as AnyObject).localizedName
                }
            }
        }
        
        self.videoCapturer = RTCVideoCapturer(deviceName: cameraID)
        self.videoSource = self.peerConnectionFactory.videoSource(
            with: self.videoCapturer,
            constraints: RTCMediaConstraints()
        )
        
        self.localVideoTrack = self.peerConnectionFactory
            .videoTrack(withID: "ARDAMSv0", source: self.videoSource)
    }
    
    func addRemoteVideoTrack(videoTrack: RTCVideoTrack) {
        if self.videoConfig == nil {
            return
        }
        
        // add a video view without position/size as it will get
        // resized and re-positioned in refreshVideoContainer
        let videoView = createVideoView()
        
        videoTrack.add(videoView)
        self.remoteVideoViews.append(VideoTrackViewPair(videoView: videoView, videoTrack: videoTrack))
        
        refreshVideoContainer()
        
        if self.localVideoView != nil {
            self.webView!.bringSubview(toFront: self.localVideoView!)
        }
    }
    
    func removeRemoteVideoTrack(videoTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            for i in 0 ..< self.remoteVideoViews.count {
                let pair = self.remoteVideoViews[i]
                if pair.videoTrack == videoTrack {
                    pair.videoView.isHidden = true
                    pair.videoView.removeFromSuperview()
                    self.remoteVideoViews.remove(at: i)
                    self.refreshVideoContainer()
                    return
                }
            }
        }
    }
    
    func refreshVideoContainer() {
        /*let n = self.remoteVideoViews.count
         
         if n == 0 {
         return
         }
         
         let rows = n < 9 ? 2 : 3
         let videosInRow = n == 2 ? 2 : Int(ceil(Float(n) / Float(rows)))
         
         let videoSize = Int(Float(self.videoConfig!.container.width) / Float(videosInRow))
         let actualRows = Int(ceil(Float(n) / Float(videosInRow)))
         
         var y = getCenter(videoCount: actualRows,
         videoSize: videoSize,
         containerSize: self.videoConfig!.container.height)
         + self.videoConfig!.container.y
         
         var videoViewIndex = 0
         
         for var row = 0; row < rows && videoViewIndex < n; row += 1 {
         var x = getCenter(videoCount: row < row - 1 || n % rows == 0 ?
         videosInRow : n - (min(n, videoViewIndex + videosInRow) - 1),
         videoSize: videoSize,
         containerSize: self.videoConfig!.container.width)
         + self.videoConfig!.container.x
         
         for var video = 0; video < videosInRow && videoViewIndex < n; video += 1 {
         let pair = self.remoteVideoViews[videoViewIndex]
         videoViewIndex += 1
         pair.videoView.frame = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(videoSize), height: CGFloat(videoSize))
         
         x += Int(videoSize)
         }
         
         y += Int(videoSize)
         }*/
    }
    
    func getCenter(videoCount: Int, videoSize: Int, containerSize: Int) -> Int {
        return lroundf(Float(containerSize - videoSize * videoCount) / 2.0)
    }
    
    func onSessionDisconnect(sessionKey: String) {
        self.sessions.removeValue(forKey: sessionKey)
        
        if self.sessions.count == 0 {
            DispatchQueue.main.sync {
                if self.localVideoView != nil {
                    self.localVideoView!.isHidden = true
                    self.localVideoView!.removeFromSuperview()
                    
                    self.localVideoView = nil
                }
            }
            
            self.localVideoTrack = nil
            self.localAudioTrack = nil
            
            self.videoSource = nil
            self.videoCapturer = nil
        }
    }
}

struct VideoTrackViewPair {
    var videoView: RTCEAGLVideoView
    var videoTrack: RTCVideoTrack
}
