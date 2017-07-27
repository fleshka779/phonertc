import Foundation

class SessionConfig {
    var isInitiator: Bool
    var turn: TurnConfig
    var streams: StreamsConfig
    
    init(data: [String:Any]) {
        self.isInitiator = data["isInitiator"] as! Bool
        
        let turnObject = data["turn"] as! [String:Any]
        self.turn = TurnConfig(
            host: turnObject["host"] as! String,
            username: turnObject["username"] as! String,
            password: turnObject["password"] as! String
        )
        
        let streamsObject = data["streams"] as! [String:Any]
        self.streams = StreamsConfig(
            audio: streamsObject["audio"] as! Bool,
            video: streamsObject["video"] as! Bool
        )
    }
}

struct TurnConfig {
    var host: String
    var username: String
    var password: String
}

struct StreamsConfig {
    var audio: Bool
    var video: Bool
}

class VideoConfig {
    var container: VideoLayoutParams
    var local: VideoLayoutParams?
    
    init(data: [String:Any]) {
        let data = data
        let containerParams = data["containerParams"]
        let localParams = data["local"]
        
        self.container = VideoLayoutParams(data: containerParams as! [String : Any])
        
        if localParams != nil {
            self.local = VideoLayoutParams(data: localParams! as! [String : Any])
        }
    }
}

class VideoLayoutParams {
    var x, y, width, height: Int
    
    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    init(data: [String:Any]) {
        let position: [AnyObject] = data["position"] as! [AnyObject]
        self.x = position[0] as! Int
        self.y = position[1] as! Int
        
        let size: [AnyObject] = data["size"] as! [AnyObject]
        self.width = size[0] as! Int
        self.height = size[1] as! Int
    }
}
