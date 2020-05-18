//
//  ChatViewController.swift
//  WebRTCHandsOn
//
//  Created by 石川 雅之 on 2020/05/18.
//  Copyright © 2020 usayuki. All rights reserved.
//

import UIKit
import WebRTC
import Starscream
import SwiftyJSON

class ChatViewController: UIViewController {

    @IBOutlet private weak var remoteVideoView: RTCEAGLVideoView!
    @IBOutlet private weak var cameraPreview: RTCCameraPreviewView!

    private var websocket: WebSocket! = nil
    private var peerConnectionFactory: RTCPeerConnectionFactory! = nil
    private var peerConnection: RTCPeerConnection! = nil
    private var remoteVideoTrack: RTCVideoTrack?
    private var audioSource: RTCAudioSource?
    private var videoSource: RTCAVFoundationVideoSource?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        remoteVideoView.delegate = self
        peerConnectionFactory = RTCPeerConnectionFactory()

        startVideo()

        websocket = WebSocket(request: URLRequest(url: URL(string:
        "wss://conf.space/WebRTCHandsOnSig/[YourID]")!))
        websocket.delegate = self
        websocket.connect()
    }

    @IBAction func connectButtonAction(_ sender: Any) {
        // Connectボタンを押した時
        if peerConnection == nil {
            LOG("make Offer")
            makeOffer()
        } else {
            LOG("peer already exist.")
        }
    }

    @IBAction func hangupButtonAction(_ sender: UIButton) {
        hangUp()
    }

    @IBAction func closeButtonAction(_ sender: UIButton) {
        websocket.disconnect()
        navigationController?.popToRootViewController(animated: true)
    }

    func LOG(_ body: String = "", function: String = #function, line: Int = #line) {
       print("[\(function) : \(line)] \(body)")
    }

    deinit {
        if peerConnection != nil {
            hangUp()
        }
        audioSource = nil
        videoSource = nil
        peerConnectionFactory = nil
    }
}

extension ChatViewController {
    private func startVideo() {
        // 音声ソースの設定
        let audioSourceConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil, optionalConstraints: nil)
        audioSource = peerConnectionFactory
            .audioSource(with: audioSourceConstraints)

        // 映像ソースの設定
        let videoSourceConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil, optionalConstraints: nil)
        videoSource = peerConnectionFactory
            .avFoundationVideoSource(with: videoSourceConstraints)

        cameraPreview.captureSession = videoSource?.captureSession
    }

    private func prepareNewConnection() -> RTCPeerConnection {
        // STUN/TURNサーバーの指定
        let configuration = RTCConfiguration()
        configuration.iceServers = [
            RTCIceServer.init(urlStrings:
                ["stun:stun.l.google.com:19302"])]
        // PeerConecctionの設定(今回はなし)
        let peerConnectionConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil)
        // PeerConnectionの初期化
        peerConnection = peerConnectionFactory.peerConnection(
            with: configuration, constraints: peerConnectionConstraints, delegate: self)

        // 音声トラックの作成
        let localAudioTrack = peerConnectionFactory
            .audioTrack(with: audioSource!, trackId: "ARDAMSa0")
        // PeerConnectionからAudioのSenderを作成
        let audioSender = peerConnection.sender(
                withKind: kRTCMediaStreamTrackKindAudio,
                streamId: "ARDAMS")
        // Senderにトラックを設定
        audioSender.track = localAudioTrack

        // 映像トラックの作成
        let localVideoTrack = peerConnectionFactory.videoTrack(
                with: videoSource!, trackId: "ARDAMSv0")
        // PeerConnectionからVideoのSenderを作成
        let videoSender = peerConnection.sender(
                withKind: kRTCMediaStreamTrackKindVideo,
                streamId: "ARDAMS")
        // Senderにトラックを設定
        videoSender.track = localVideoTrack

        return peerConnection
    }

    private func hangUp() {
        if peerConnection != nil {
            if peerConnection.iceConnectionState != RTCIceConnectionState.closed {
                peerConnection.close()
                let jsonClose: JSON = [
                    "type": "close"
                ]
                LOG("sending close message")
                websocket.write(string: jsonClose.rawString()!)
            }
            if remoteVideoTrack != nil {
                remoteVideoTrack?.remove(remoteVideoView)
            }
            remoteVideoTrack = nil
            peerConnection = nil
            LOG("peerConnection is closed.")
        }
    }

    private func sendSDP(_ desc: RTCSessionDescription) {
        LOG("---sending sdp ---")
        let jsonSdp: JSON = [
            "sdp": desc.sdp, // SDP本体
            "type": RTCSessionDescription.string(
                for: desc.type) // offer か answer か
        ]
        // JSONを生成
        let message = jsonSdp.rawString()!
        LOG("sending SDP=" + message)
        // 相手に送信
        websocket.write(string: message)
    }

    private func makeOffer() {
        // PeerConnectionを生成
        peerConnection = prepareNewConnection()
        // Offerの設定 今回は映像も音声も受け取る
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
                ], optionalConstraints: nil)
        let offerCompletion = {
            (offer: RTCSessionDescription?, error: Error?) in
            // Offerの生成が完了した際の処理
            if error != nil { return }
            self.LOG("createOffer() succsess")

            let setLocalDescCompletion = {(error: Error?) in
                // setLocalDescCompletionが完了した際の処理
                if error != nil { return }
                self.LOG("setLocalDescription() succsess")
                // 相手に送る
                self.sendSDP(offer!)
            }
            // 生成したOfferを自分のSDPとして設定
            self.peerConnection.setLocalDescription(offer!,
                completionHandler: setLocalDescCompletion)
        }
        // Offerを生成
        self.peerConnection.offer(for: constraints,
            completionHandler: offerCompletion)
    }

    private func setAnswer(_ answer: RTCSessionDescription) {
        if peerConnection == nil {
            LOG("peerConnection NOT exist!")
            return
        }
        // 受け取ったSDPを相手のSDPとして設定
        self.peerConnection.setRemoteDescription(answer,
            completionHandler: {
            (error: Error?) in
            if error == nil {
                self.LOG("setRemoteDescription(answer) succsess")
            } else {
                self.LOG("setRemoteDescription(answer) ERROR: " + error.debugDescription)
            }
        })
    }

    private func addIceCandidate(_ candidate: RTCIceCandidate) {
        if peerConnection != nil {
            peerConnection.add(candidate)
        } else {
            LOG("PeerConnection not exist!")
        }
    }

    private func sendIceCandidate(_ candidate: RTCIceCandidate) {
        LOG("---sending ICE candidate ---")
        let jsonCandidate: JSON = [
            "type": "candidate",
            "ice": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid!
            ]
        ]
        let message = jsonCandidate.rawString()!
        LOG("sending candidate=" + message)
        websocket.write(string: message)
    }

    private func setOffer(_ offer: RTCSessionDescription) {
        if peerConnection != nil {
            LOG("peerConnection alreay exist!")
        }
        // PeerConnectionを生成する
        peerConnection = prepareNewConnection()
        self.peerConnection.setRemoteDescription(offer, completionHandler: {(error: Error?) in
            if error == nil {
                self.LOG("setRemoteDescription(offer) succsess")
                // setRemoteDescriptionが成功したらAnswerを作る
                self.makeAnswer()
            } else {
                self.LOG("setRemoteDescription(offer) ERROR: " + error.debugDescription)
            }
        })
    }

    private func makeAnswer() {
        LOG("sending Answer. Creating remote session description...")
        if peerConnection == nil {
            LOG("peerConnection NOT exist!")
            return
        }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let answerCompletion = { (answer: RTCSessionDescription?, error: Error?) in
            if error != nil { return }
            self.LOG("createAnswer() succsess")
            let setLocalDescCompletion = {(error: Error?) in
                if error != nil { return }
                self.LOG("setLocalDescription() succsess")
                // 相手に送る
                self.sendSDP(answer!)
            }
            self.peerConnection.setLocalDescription(answer!, completionHandler: setLocalDescCompletion)
        }
        // Answerを生成
        self.peerConnection.answer(for: constraints, completionHandler: answerCompletion)
    }
}

extension ChatViewController: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        LOG()
        switch event {
        case .text(let text):
            LOG("message: \(text)")
            // 受け取ったメッセージをJSONとしてパース
            let jsonMessage = JSON(parseJSON: text)
            let type = jsonMessage["type"].stringValue
            switch (type) {
            case "answer":
                // answerを受け取った時の処理
                LOG("Received answer ...")
                let answer = RTCSessionDescription(
                    type: RTCSessionDescription.type(for: type),
                    sdp: jsonMessage["sdp"].stringValue)
                setAnswer(answer)
            case "candidate":
                LOG("Received ICE candidate ...")
                let candidate = RTCIceCandidate(
                    sdp: jsonMessage["ice"]["candidate"].stringValue,
                    sdpMLineIndex:
                        jsonMessage["ice"]["sdpMLineIndex"].int32Value,
                    sdpMid: jsonMessage["ice"]["sdpMid"].stringValue)
                addIceCandidate(candidate)
            case "offer":
                // offerを受け取った時の処理
                LOG("Received offer ...")
                let offer = RTCSessionDescription(
                    type: RTCSessionDescription.type(for: type),
                    sdp: jsonMessage["sdp"].stringValue)
                setOffer(offer)
            case "close":
                LOG("peer is closed ...")
                hangUp()
            default:
                return
            }
        default:
            return
        }
    }
}

extension ChatViewController: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        // 接続情報交換の状況が変化した際に呼ばれます
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // 映像/音声が追加された際に呼ばれます
        LOG("-- peer.onaddstream()")
        DispatchQueue.main.async(execute: { () -> Void in
            // mainスレッドで実行
            if (stream.videoTracks.count > 0) {
                // ビデオのトラックを取り出して
                self.remoteVideoTrack = stream.videoTracks[0]
                // remoteVideoViewに紐づける
                self.remoteVideoTrack?.add(self.remoteVideoView)
            }
        })
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // 映像/音声削除された際に呼ばれます
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // 接続情報の交換が必要になった際に呼ばれます
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        // PeerConnectionの接続状況が変化した際に呼ばれます
        var state = ""
        switch (newState) {
        case RTCIceConnectionState.checking:
            state = "checking"
        case RTCIceConnectionState.completed:
            state = "completed"
        case RTCIceConnectionState.connected:
            state = "connected"
        case RTCIceConnectionState.closed:
            state = "closed"
            hangUp()
        case RTCIceConnectionState.failed:
            state = "failed"
            hangUp()
        case RTCIceConnectionState.disconnected:
            state = "disconnected"
        default:
            break
        }
        LOG("ICE connection Status has changed to \(state)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        // 接続先候補の探索状況が変化した際に呼ばれます
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // Candidate(自分への接続先候補情報)が生成された際に呼ばれます
        if candidate.sdpMid != nil {
            sendIceCandidate(candidate)
        } else {
            LOG("empty ice event")
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Candidateが削除された際に呼ばれます
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // DataChannelが作られた際に呼ばれます
    }
}

extension ChatViewController: RTCEAGLVideoViewDelegate {
    func videoView(_ videoView: RTCEAGLVideoView, didChangeVideoSize size: CGSize) {
        let width = self.view.frame.width
        let height =
            self.view.frame.width * size.height / size.width
        videoView.frame = CGRect(
            x: 0,
            y: (self.view.frame.height - height) / 2,
            width: width,
            height: height)
    }
}
