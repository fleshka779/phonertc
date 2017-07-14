import Foundation

class Session {
    var plugin: PhoneRTCPlugin
    var config: SessionConfig
    var constraints: RTCMediaConstraints
    var peerConnection: RTCPeerConnection!
    var pcObserver: PCObserver!
    var queuedRemoteCandidates: [RTCICECandidate]?
    var peerConnectionFactory: RTCPeerConnectionFactory
    var callbackId: String
    var stream: RTCMediaStream?
    var videoTrack: RTCVideoTrack?
    var sessionKey: String
    
    init(plugin: PhoneRTCPlugin,
         peerConnectionFactory: RTCPeerConnectionFactory,
         config: SessionConfig,
         callbackId: String,
         sessionKey: String) {
        self.plugin = plugin
        self.queuedRemoteCandidates = []
        self.config = config
        self.peerConnectionFactory = peerConnectionFactory
        self.callbackId = callbackId
        self.sessionKey = sessionKey
        
        // initialize basic media constraints
        self.constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                RTCPair(key: "OfferToReceiveAudio", value: "true"),
                RTCPair(key: "OfferToReceiveVideo", value:
                    self.plugin.videoConfig == nil ? "false" : "true"),
                ],
            
            optionalConstraints: [
                RTCPair(key: "internalSctpDataChannels", value: "true"),
                RTCPair(key: "DtlsSrtpKeyAgreement", value: "true")
            ]
        )
    }
    
    func call() {
        // create a list of ICE servers
        var iceServers: [RTCICEServer] = []
        iceServers.append(RTCICEServer(
            uri: URL(string: "stun:stun.l.google.com:19302"),
            username: "",
            password: ""))
        
        iceServers.append(RTCICEServer(
            uri: URL(string: self.config.turn.host),
            username: self.config.turn.username,
            password: self.config.turn.password))
        
        // initialize a PeerConnection
        self.pcObserver = PCObserver(session: self)
        self.peerConnection =
            peerConnectionFactory.peerConnection(withICEServers: iceServers,
                                                 constraints: self.constraints,
                                                 delegate: self.pcObserver)
        
        // create a media stream and add audio and/or video tracks
        createOrUpdateStream()
        
        // create offer if initiator
        if self.config.isInitiator {
            self.peerConnection.createOffer(with: SessionDescriptionDelegate(session: self),
                                            constraints: constraints)
        }
    }
    
    func createOrUpdateStream() {
        if self.stream != nil {
            self.peerConnection.remove(self.stream)
            self.stream = nil
        }
        
        self.stream = peerConnectionFactory.mediaStream(withLabel: "ARDAMS")
        
        if self.config.streams.audio {
            // init local audio track if needed
            if self.plugin.localAudioTrack == nil {
                self.plugin.initLocalAudioTrack()
            }
            
            self.stream!.addAudioTrack(self.plugin.localAudioTrack!)
        }
        
        if self.config.streams.video {
            // init local video track if needed
            if self.plugin.localVideoTrack == nil {
                self.plugin.initLocalVideoTrack()
            }
            
            self.stream!.addVideoTrack(self.plugin.localVideoTrack!)
        }
        
        self.peerConnection.add(self.stream)
    }
    
    func receiveMessage(message: String) {
        // Parse the incoming JSON message.
        var error : NSError?
        let data : Any?
        do {
            data = try JSONSerialization.jsonObject(
                with: message.data(using: String.Encoding.utf8)!,
                options: JSONSerialization.ReadingOptions())
        } catch let error1 as NSError {
            error = error1
            data = nil
        }
        if let object = data as? [String : Any] {
            // Log the message to console.
            print("Received Message: \(object)")
            // If the message has a type try to handle it.
            if let type = object["type"] as? String {
                switch type {
                case "candidate":
                    let mid: String = object["id"] as! String
                    let sdpLineIndex: Int = object["label"] as! Int
                    let sdp: String = object["candidate"] as! String
                    
                    let candidate = RTCICECandidate(
                        mid: mid,
                        index: sdpLineIndex,
                        sdp: sdp
                    )
                    
                    if self.queuedRemoteCandidates != nil {
                        self.queuedRemoteCandidates?.append(candidate!)
                    } else {
                        self.peerConnection.add(candidate)
                    }
                    
                case "offer", "answer":
                    if let sdpString = object["sdp"] as? String {
                        let sdp = RTCSessionDescription(type: type, sdp: self.preferISAC(sdpDescription: sdpString))
                        self.peerConnection.setRemoteDescriptionWith(SessionDescriptionDelegate(session: self),
                                                                     sessionDescription: sdp)
                    }
                case "bye":
                    self.disconnect(sendByeMessage: false)
                default:
                    print("Invalid message \(message)")
                }
            }
        } else {
            // If there was an error parsing then print it to console.
            if let parseError = error {
                print("There was an error parsing the client message: \(parseError.localizedDescription)")
            }
            // If there is no data then exit.
            return
        }
    }
    
    func disconnect(sendByeMessage: Bool) {
        if self.videoTrack != nil {
            self.removeVideoTrack(videoTrack: self.videoTrack!)
        }
        
        if self.peerConnection != nil {
            if sendByeMessage {
                let json = [
                    "type": "bye"
                ]
                
                let data = try? JSONSerialization.data(withJSONObject: json,
                                                       options: JSONSerialization.WritingOptions())
                
                self.sendMessage(message: data!)
            }
            
            self.peerConnection.close()
            self.peerConnection = nil
            self.queuedRemoteCandidates = nil
        }
        
        let json = [
            "type": "__disconnected"
        ]
        
        let data = try? JSONSerialization.data(withJSONObject: json,
                                               options: JSONSerialization.WritingOptions())
        
        self.sendMessage(message: data!)
        
        self.plugin.onSessionDisconnect(sessionKey: self.sessionKey)
    }
    
    func addVideoTrack(videoTrack: RTCVideoTrack) {
        self.videoTrack = videoTrack
        self.plugin.addRemoteVideoTrack(videoTrack: videoTrack)
    }
    
    func removeVideoTrack(videoTrack: RTCVideoTrack) {
        self.plugin.removeRemoteVideoTrack(videoTrack: videoTrack)
    }
    
    func preferISAC(sdpDescription: String) -> String {
        var mLineIndex = -1
        var isac16kRtpMap: String?
        
        let origSDP = sdpDescription.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = origSDP.components(separatedBy: "\n")
        let isac16kRegex = try? NSRegularExpression(
            pattern: "^a=rtpmap:(\\d+) ISAC/16000[\r]?$",
            options: NSRegularExpression.Options())
        
        var i = 0
        while (i < lines.count) && (mLineIndex == -1 || isac16kRtpMap == nil){
            i += 1
            let line = lines[i]
            if line.hasPrefix("m=audio ") {
                mLineIndex = i
                continue
            }
            isac16kRtpMap = self.firstMatch(pattern: isac16kRegex!, string: line)
            
        }
        
        if mLineIndex == -1 {
            print("No m=audio line, so can't prefer iSAC")
            return origSDP
        }
        
        if isac16kRtpMap == nil {
            print("No ISAC/16000 line, so can't prefer iSAC")
            return origSDP
        }
        
        let origMLineParts = lines[mLineIndex].components(separatedBy: " ")
        
        var newMLine: [String] = []
        var origPartIndex = 0;
        
        // Format is: m=<media> <port> <proto> <fmt> ...
        newMLine.append(origMLineParts[origPartIndex])
        origPartIndex+=1
        newMLine.append(origMLineParts[origPartIndex])
        origPartIndex+=1
        newMLine.append(origMLineParts[origPartIndex])
        origPartIndex+=1
        newMLine.append(isac16kRtpMap!)
        
        while origPartIndex < origMLineParts.count {
            if isac16kRtpMap != origMLineParts[origPartIndex] {
                newMLine.append(origMLineParts[origPartIndex])
            }
            origPartIndex += 1
        }
        
        lines[mLineIndex] = newMLine.joined(separator: " ")
        return lines.joined(separator: "\r\n")
    }
    
    func firstMatch(pattern: NSRegularExpression, string: String) -> String? {
        let nsString = string as NSString
        
        let result = pattern.firstMatch(in: string,
                                        options: NSRegularExpression.MatchingOptions(),
                                        range: NSMakeRange(0, nsString.length))
        
        if result == nil {
            return nil
        }
        
        return nsString.substring(with: result!.rangeAt(1))
    }
    
    func sendMessage(message:Data) {
        self.plugin.sendMessage(callbackId: self.callbackId, message: message)
    }
}

