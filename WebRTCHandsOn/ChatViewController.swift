//
//  ChatViewController.swift
//  WebRTCHandsOn
//
//  Created by 石川 雅之 on 2020/05/18.
//  Copyright © 2020 usayuki. All rights reserved.
//

import UIKit
import WebRTC

class ChatViewController: UIViewController {

    @IBOutlet private weak var remoteVideoView: RTCEAGLVideoView!
    @IBOutlet private weak var cameraPreview: RTCCameraPreviewView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

}
