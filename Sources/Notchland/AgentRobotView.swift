import SceneKit
import SwiftUI

/// Ajan kartındaki robotun ruh hâli; oturum durumundan türetilir.
enum RobotMood: Equatable {
    case working
    case waiting
    case idle
    /// Durumu okunamayan ajan (Cursor): uyanık ama nötr.
    case unknown

    var glow: NSColor {
        switch self {
        case .working: NSColor(red: 0.3, green: 1, blue: 0.55, alpha: 1)
        case .waiting: NSColor(red: 1, green: 0.62, blue: 0.15, alpha: 1)
        case .idle: NSColor(red: 0.4, green: 0.5, blue: 0.68, alpha: 1)
        case .unknown: NSColor(white: 0.85, alpha: 1)
        }
    }
}

/// SceneKit ile çizilen 3B robot. Fare olaylarını almaz; tıklamayı çevresindeki düğme karşılar.
struct AgentRobotView: NSViewRepresentable {
    let mood: RobotMood
    let tint: NSColor
    /// Değiştikçe robot bir tur döner (üzerine gelindiğinde).
    let spinCount: Int

    func makeCoordinator() -> AgentRobot { AgentRobot(tint: tint) }

    func makeNSView(context: Context) -> PassiveSCNView {
        let view = PassiveSCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.isPlaying = true
        context.coordinator.apply(mood)
        context.coordinator.spinCount = spinCount
        return view
    }

    func updateNSView(_ view: PassiveSCNView, context: Context) {
        context.coordinator.apply(mood)
        if context.coordinator.spinCount != spinCount {
            context.coordinator.spinCount = spinCount
            context.coordinator.spin()
        }
    }

    static func dismantleNSView(_ view: PassiveSCNView, coordinator: AgentRobot) {
        view.isPlaying = false
        view.scene = nil
    }
}

final class PassiveSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Basit geometrilerden kurulan robot; ruh hâline göre SCNAction döngüleri oynatır.
final class AgentRobot {
    let scene = SCNScene()
    let camera = SCNNode()
    var spinCount = 0

    /// Sallanma (yaw) → dönüş → süzülen gövde: her katman kendi animasyonunu taşır, çakışmaz.
    private let sway = SCNNode()
    private let spinner = SCNNode()
    private let body = SCNNode()
    private let head = SCNNode()
    private let leftArm = SCNNode()
    private let rightArm = SCNNode()
    private let antennaTip = SCNNode()
    private let groundGlow = SCNNode()
    private var eyes: [SCNNode] = []
    private let glow = SCNMaterial()
    private let groundMaterial = SCNMaterial()
    private var mood: RobotMood?

    init(tint: NSColor) {
        scene.background.contents = NSColor.clear
        build(tint: tint)
        setUpLights()

        let lens = SCNCamera()
        lens.fieldOfView = 30
        lens.zNear = 0.1
        camera.camera = lens
        camera.position = SCNVector3(0, 0.35, 5.3)
        camera.look(at: SCNVector3(0, 0.05, 0))
        scene.rootNode.addChildNode(camera)
    }

    // MARK: Yapı

    private func build(tint: NSColor) {
        let shell = Self.material(tint, shininess: 0.55)
        let face = Self.material(NSColor(white: 0.93, alpha: 1), shininess: 0.7)
        let dark = Self.material(NSColor(white: 0.12, alpha: 1), shininess: 0.9)
        glow.lightingModel = .constant
        groundMaterial.lightingModel = .constant
        groundMaterial.blendMode = .add
        groundMaterial.writesToDepthBuffer = false

        scene.rootNode.addChildNode(sway)
        sway.addChildNode(spinner)
        spinner.addChildNode(body)

        let torso = SCNNode(geometry: SCNBox(width: 0.9, height: 0.75, length: 0.62, chamferRadius: 0.2))
        torso.geometry?.firstMaterial = shell
        torso.position.y = -0.18
        body.addChildNode(torso)

        let panel = SCNNode(geometry: SCNBox(width: 0.44, height: 0.24, length: 0.06, chamferRadius: 0.06))
        panel.geometry?.firstMaterial = dark
        panel.position = SCNVector3(0, -0.12, 0.31)
        body.addChildNode(panel)
        for x in [-0.11, 0.0, 0.11] {
            let light = SCNNode(geometry: SCNSphere(radius: 0.035))
            light.geometry?.firstMaterial = glow
            light.position = SCNVector3(x, -0.12, 0.345)
            body.addChildNode(light)
        }

        let thruster = SCNNode(geometry: SCNCone(topRadius: 0.26, bottomRadius: 0.14, height: 0.16))
        thruster.geometry?.firstMaterial = dark
        thruster.position.y = -0.63
        body.addChildNode(thruster)

        let neck = SCNNode(geometry: SCNCylinder(radius: 0.12, height: 0.16))
        neck.geometry?.firstMaterial = dark
        neck.position.y = 0.26
        body.addChildNode(neck)

        head.position.y = 0.62
        body.addChildNode(head)
        let skull = SCNNode(geometry: SCNBox(width: 1.0, height: 0.68, length: 0.72, chamferRadius: 0.24))
        skull.geometry?.firstMaterial = face
        head.addChildNode(skull)
        let visor = SCNNode(geometry: SCNBox(width: 0.78, height: 0.44, length: 0.06, chamferRadius: 0.13))
        visor.geometry?.firstMaterial = dark
        visor.position.z = 0.35
        head.addChildNode(visor)
        for x in [-0.17, 0.17] {
            let eye = SCNNode(geometry: SCNBox(width: 0.13, height: 0.2, length: 0.03, chamferRadius: 0.06))
            eye.geometry?.firstMaterial = glow
            eye.position = SCNVector3(x, 0.01, 0.385)
            head.addChildNode(eye)
            eyes.append(eye)
        }
        for x in [-0.53, 0.53] {
            let ear = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 0.08))
            ear.geometry?.firstMaterial = shell
            ear.eulerAngles.z = .pi / 2
            ear.position.x = x
            head.addChildNode(ear)
        }
        let antenna = SCNNode(geometry: SCNCylinder(radius: 0.022, height: 0.26))
        antenna.geometry?.firstMaterial = dark
        antenna.position.y = 0.46
        head.addChildNode(antenna)
        antennaTip.geometry = SCNSphere(radius: 0.065)
        antennaTip.geometry?.firstMaterial = glow
        antennaTip.position.y = 0.62
        head.addChildNode(antennaTip)

        for (arm, x) in [(leftArm, -0.55), (rightArm, 0.55)] {
            arm.position = SCNVector3(x, 0.08, 0)
            body.addChildNode(arm)
            let limb = SCNNode(geometry: SCNCapsule(capRadius: 0.085, height: 0.5))
            limb.geometry?.firstMaterial = shell
            limb.position.y = -0.2
            arm.addChildNode(limb)
            let hand = SCNNode(geometry: SCNSphere(radius: 0.1))
            hand.geometry?.firstMaterial = dark
            hand.position.y = -0.46
            arm.addChildNode(hand)
        }

        groundGlow.geometry = SCNCylinder(radius: 0.5, height: 0.002)
        groundGlow.geometry?.firstMaterial = groundMaterial
        groundGlow.position.y = -1.0
        scene.rootNode.addChildNode(groundGlow)
    }

    private func setUpLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(key)

        /// Arkadan gelen soğuk ışık siluetin karanlık panelde kaybolmasını önler.
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 500
        rim.light?.color = NSColor(red: 0.6, green: 0.75, blue: 1, alpha: 1)
        rim.eulerAngles = SCNVector3(-0.3, .pi * 0.85, 0)
        scene.rootNode.addChildNode(rim)
    }

    private static func material(_ color: NSColor, shininess: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = color
        material.specular.contents = NSColor(white: 0.8, alpha: 1)
        material.shininess = shininess
        return material
    }

    // MARK: Hareket

    func spin() {
        spinner.runAction(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.7).easing(.easeInEaseOut), forKey: "spin")
    }

    func apply(_ mood: RobotMood) {
        guard mood != self.mood else { return }
        let isFirst = self.mood == nil
        self.mood = mood

        for node in [sway, body, head, leftArm, rightArm, antennaTip] + eyes { node.removeAllActions() }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = isFirst ? 0 : 0.35
        glow.diffuse.contents = mood.glow
        groundMaterial.diffuse.contents = mood.glow.withAlphaComponent(mood == .idle ? 0.12 : 0.3)
        body.position = SCNVector3Zero
        head.eulerAngles = SCNVector3Zero
        leftArm.eulerAngles = SCNVector3Zero
        rightArm.eulerAngles = SCNVector3Zero
        antennaTip.scale = SCNVector3(1, 1, 1)
        antennaTip.opacity = 1
        for eye in eyes { eye.scale = SCNVector3(1, 1, 1) }

        switch mood {
        case .working:
            leftArm.eulerAngles.x = -0.7
            rightArm.eulerAngles.x = -0.7
        case .waiting:
            rightArm.eulerAngles.z = 2.5
            head.eulerAngles.z = 0.18
        case .idle:
            head.eulerAngles.x = 0.32
            leftArm.eulerAngles.z = -0.12
            rightArm.eulerAngles.z = 0.12
            for eye in eyes { eye.scale = SCNVector3(1.15, 0.14, 1) }
        case .unknown:
            break
        }
        SCNTransaction.commit()

        sway.runAction(.repeatForever(.sequence([
            Self.ease(.rotateTo(x: 0, y: 0.4, z: 0, duration: 2.6, usesShortestUnitArc: true)),
            Self.ease(.rotateTo(x: 0, y: -0.4, z: 0, duration: 2.6, usesShortestUnitArc: true)),
        ])))

        switch mood {
        case .working:
            body.runAction(Self.bob(0.07, period: 1.0))
            leftArm.runAction(Self.oscillate(x: 0.18, period: 0.3))
            rightArm.runAction(.sequence([.wait(duration: 0.15), Self.oscillate(x: 0.18, period: 0.3)]))
            head.runAction(.repeatForever(.sequence([
                Self.ease(.rotateTo(x: 0, y: 0.3, z: 0, duration: 0.7, usesShortestUnitArc: true)),
                .wait(duration: 0.8),
                Self.ease(.rotateTo(x: 0, y: -0.3, z: 0, duration: 0.7, usesShortestUnitArc: true)),
                .wait(duration: 0.8),
            ])))
            antennaTip.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.25, duration: 0.25), .fadeOpacity(to: 1, duration: 0.25)])))
            for eye in eyes { eye.runAction(Self.blink) }
        case .waiting:
            body.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.2, z: 0, duration: 0.22).easing(.easeOut),
                .moveBy(x: 0, y: -0.2, z: 0, duration: 0.22).easing(.easeIn),
                .wait(duration: 0.7),
            ])))
            rightArm.runAction(.repeatForever(.sequence([
                Self.ease(.rotateTo(x: 0, y: 0, z: 2.85, duration: 0.25)),
                Self.ease(.rotateTo(x: 0, y: 0, z: 2.2, duration: 0.25)),
            ])))
            antennaTip.runAction(.repeatForever(.sequence([.scale(to: 1.5, duration: 0.3), .scale(to: 1, duration: 0.3)])))
            for eye in eyes { eye.runAction(Self.blink) }
        case .idle:
            body.runAction(Self.bob(0.03, period: 3.2))
            antennaTip.runAction(.fadeOpacity(to: 0.35, duration: 0.6))
        case .unknown:
            body.runAction(Self.bob(0.05, period: 2.2))
            for eye in eyes { eye.runAction(Self.blink) }
        }
    }

    private static func ease(_ action: SCNAction) -> SCNAction { action.easing(.easeInEaseOut) }

    private static func bob(_ height: CGFloat, period: TimeInterval) -> SCNAction {
        .repeatForever(.sequence([
            ease(.moveBy(x: 0, y: height, z: 0, duration: period / 2)),
            ease(.moveBy(x: 0, y: -height, z: 0, duration: period / 2)),
        ]))
    }

    /// Kollar klavyeye vuruyormuş gibi öne arkaya gider.
    private static func oscillate(x: CGFloat, period: TimeInterval) -> SCNAction {
        .repeatForever(.sequence([
            ease(.rotateBy(x: x, y: 0, z: 0, duration: period / 2)),
            ease(.rotateBy(x: -x, y: 0, z: 0, duration: period / 2)),
        ]))
    }

    private static var blink: SCNAction {
        .repeatForever(.sequence([
            .wait(duration: 2.8, withRange: 1.5),
            .scaleY(to: 0.1, duration: 0.07),
            .scaleY(to: 1, duration: 0.09),
        ]))
    }
}

private extension SCNAction {
    func easing(_ mode: SCNActionTimingMode) -> SCNAction {
        timingMode = mode
        return self
    }

    /// Yalnızca y ölçeği değişir; SCNAction'da hazır karşılığı yok.
    static func scaleY(to value: CGFloat, duration: TimeInterval) -> SCNAction {
        .customAction(duration: duration) { node, elapsed in
            let progress = duration > 0 ? CGFloat(elapsed) / CGFloat(duration) : 1
            node.scale.y = node.scale.y + (value - node.scale.y) * progress
        }
    }
}
