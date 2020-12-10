//
//  ContentView.swift
//  BlindCompass3
//
//  Created by Tony Malykh on 11/25/20.
//

import AudioKit
import AVFoundation
import CoreLocation
import Foundation
import MediaPlayer
import SwiftUI

class Helper {
    class func alertMessage(title: String, message: String) {
        let alertVC = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default) { (action: UIAlertAction) in
        }
        alertVC.addAction(okAction)
        
        let viewController = UIApplication.shared.windows.first!.rootViewController!
        viewController.present(alertVC, animated: true, completion: nil)
    }    

}

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                Button(action: {
                    self.speakHeading()
                }) {
                    Text("Speak heading")
                }
                Button(action: {
                    self.lockUnlock()
                }) {
                    if (!lockedMode) {
                        Text("Lock direction")
                    } else {
                        Text("Unlock direction")
                    }
                }
            }
            /*
            Text("Hello, world!")
                .padding()
            */
                .navigationBarTitle(Text("Blind Compass"))
        }.onAppear(perform: initialize)
        .onReceive(timer) { time in
            //print("The time is now \(time)")
            onTimer()
        }        
    }
    
    var engine = AudioEngine()
    var oscillator = Oscillator()
    var oscillatorMajor = Oscillator()
    var oscillatorMinor = Oscillator()
    let defaultAmplitude:Float = 0.2
    @State private var oscillators:[Oscillator] = []
    @State private var mixer = Mixer()
    @State private var panner:Panner = Panner(Mixer())
    @State private var currentLocation:CLLocation? = nil
    @State private var initialLocation:CLLocation? = nil
    @State private var currentHeading:Float = 0
    @State private var previousHeading:Float = 0
    @State private var lockedMode:Bool = false
    @State private var lockedOnTrack:Bool = false
    @State private var lockedHeading:Float = 0
    let locationManager: CLLocationManager = CLLocationManager()
    let locationDelegate = LocationDelegate()
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    @State private var player: AVAudioPlayer?
    @State var countSteps:Bool = true
    private func initialize() {
        // This prevents phone from locking the screen in a minute:
        UIApplication.shared.isIdleTimerDisabled = true
        guard let url = Bundle.main.url(forResource: "Sounds/save-object", withExtension: "wav") else {return}
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)            
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.wav.rawValue)
        } catch let error {
            print(error.localizedDescription)
        }            
        mixer = Mixer(oscillator, oscillatorMajor)
        mixer.volume = 0.5
        oscillator.amplitude = defaultAmplitude
        oscillatorMajor.amplitude = defaultAmplitude
        panner = Panner(mixer)
        engine.output = panner
        do {
            try engine.start()
        } catch {
            print("AudioKit failed to start :(")
            return
        }
        oscillator.start()
        oscillatorMajor.start()

        if (!CLLocationManager.headingAvailable()) {
            Helper.alertMessage(title:"Alert", message:"Magnetic compass is not available on this device!")
            return
        }

        locationManager.delegate = locationDelegate
        locationManager.startUpdatingHeading()
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationDelegate.headingCallback = onNewHeading
        locationDelegate.locationCallback = onNewLocation
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            onBluetoothPlay()
            return MPRemoteCommandHandlerStatus.success
        }

        commandCenter.pauseCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            onBluetoothPlay()
            return MPRemoteCommandHandlerStatus.success
        }        
        let nextHandler = { (commandEvent:MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
            onBluetoothNext()
            return MPRemoteCommandHandlerStatus.success
        }
        commandCenter.nextTrackCommand.addTarget(handler:nextHandler)
        commandCenter.seekForwardCommand.addTarget(handler:nextHandler)
        commandCenter.skipForwardCommand.addTarget(handler:nextHandler)
        let previousHandler = { (commandEvent:MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
            onBluetoothPrevious()
            return MPRemoteCommandHandlerStatus.success
        }
        commandCenter.previousTrackCommand.addTarget(handler:previousHandler)
        commandCenter.seekBackwardCommand.addTarget(handler:previousHandler)
        commandCenter.skipBackwardCommand.addTarget(handler:previousHandler)
    }
    @State private var oscillatorIndex:Int = 0
    private func onTimer() {
        /*
        let n = oscillators.count
        let prevIndex = oscillatorIndex
        oscillatorIndex += 1
        oscillators[prevIndex % n].amplitude = 0
        oscillators[oscillatorIndex % n].amplitude = 1.0
        */
    }
    
    let synthesizer = AVSpeechSynthesizer()
    let regions:[String] = [
        "North",
        "NorthEast",
        "East",
        "SouthEast",
        "South",
        "SouthWest",
        "West",
        "NorthWest",
        "North",
    ]
    private func getRegion() -> String {
        var index:Int = Int(floor((currentHeading + 22.5) / 45))
        let region = regions[index]
        return region
    }
    
    private func getHeadingString() -> String {
        let headingInt = Int(currentHeading.rounded())
        var str = String(format:"%d degrees", headingInt)
        let region = getRegion()
        str = "\(str) \(region)"
        return str
    }
    private func speak(str:String) {
        let utterance = AVSpeechUtterance(string: str)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.70
        synthesizer.speak(utterance)    
    }
    private func speakHeading() {
        speak(str:getHeadingString())
    }
    private func lockUnlock() {
        if (!lockedMode) {
            lockedMode = true
            lockedOnTrack = true
            lockedHeading = currentHeading
            var message = getHeadingString()
            message = "Locked on " + message
            if (countSteps) {
                lastReportedDistance = 0
                if (currentLocation == nil) {
                    message += " Location not available"
                    initialLocation = nil
                } else {
                    message += " counting steps"
                    initialLocation = currentLocation
                }
            }
            speak(str:message)
            oscillator.amplitude = 0
            oscillatorMajor.amplitude = 0
            processNewHeading()
        } else {
            lockedMode = false
            panner.pan = 0
            oscillator.amplitude = defaultAmplitude
            oscillatorMajor.amplitude = defaultAmplitude
            speak(str:"Unlocked")
            processNewHeading()
        }    
    }
    private func onBluetoothPlay() {
        speakHeading()
    }
    private func onBluetoothNext() {
        lockUnlock()
    }
    private func onBluetoothPrevious() {
        //Helper.alertMessage(title:"Not implemented", message:"Not implemented")
    }
    
    private func onNewLocation(newLocation:CLLocation) {
        currentLocation = newLocation
    }
    let baseFreq:Float = 440
    let semitone:Float = pow(2, (1/12))
    let onTrackThreshold:Float = 9
    let offTrackThreshold:Float = 10
    let alignedThreshold:Float = 10
    @State var aligned:Bool = false
    let distanceThreshold:Float = 10
    @State var lastReportedDistance:Float = 0
    private func onNewHeading(newHeading:CLLocationDirection) {
        previousHeading = currentHeading
        currentHeading = Float(newHeading)
        processNewHeading()
    }
    private func processNewHeading() {
        if (!lockedMode) {
            let halfN = 12
            let n = halfN + halfN
            var quadrant:Int = Int(floor(currentHeading/90))
            var previousQuadrant:Int = Int(floor(previousHeading/90))
            if (!aligned && (previousQuadrant != quadrant)) {
                aligned = true
                speak(str:getRegion())
            }
            var quadrantHeading:Float = currentHeading.truncatingRemainder(dividingBy: 90)
            if ((quadrantHeading > alignedThreshold) && (quadrantHeading < 90 - alignedThreshold)) {
                aligned = false
            }
            var bucket: Int = Int((quadrantHeading / 90 * Float(n)).rounded(.towardZero))
            if (bucket >= n) {
                bucket = n - 1
            }
            
            var note = bucket - halfN
            if (note >= 0) {
                note += 1
            }
            let freq = baseFreq * Float(pow(semitone, Float(note)))
            
            oscillator.frequency = baseFreq
            oscillatorMajor.frequency = freq
        } else {
            // locked mode
            var deviation:Float = currentHeading - lockedHeading
            // Normalize deviation to be between -180 and 180
            while (deviation > 180) {
                deviation -= 360
            }
            while (deviation < -180) {
                deviation += 360
            }
            let deviationAbs = deviation.magnitude
            var deviationSign:Float
            if (deviation >= 0) {
                deviationSign = 1
            } else {
                deviationSign = -1
            }
            if ((!lockedOnTrack) && (deviationAbs < onTrackThreshold)) {
                lockedOnTrack = true
                player!.play()
                oscillator.amplitude = 0
                oscillatorMajor.amplitude = 0
            }
            if ((lockedOnTrack) && (deviationAbs >= offTrackThreshold)) {
                lockedOnTrack = false
                oscillator.amplitude = defaultAmplitude
                oscillatorMajor.amplitude = defaultAmplitude
            }
            let panValue = min(deviationAbs / 90, 1)
            panner.pan = -deviationSign * panValue
            let note = min(deviationAbs / 90, 1) * 12
            let freq = baseFreq * Float(pow(semitone, Float(note)))
            oscillatorMajor.frequency = freq
            if (countSteps) {
                if ((currentLocation != nil) && (initialLocation != nil)) {
                    let distance = currentLocation!.distance(from:initialLocation!)
                    let distanceFeet:Float = Float(Measurement(value: distance, unit: UnitLength.meters).converted(to: UnitLength.feet).value)
                    if ((distanceFeet - lastReportedDistance).magnitude  > distanceThreshold) {
                        var step:Float = 0
                        if (distanceFeet > lastReportedDistance) {
                            step = distanceThreshold
                        } else {
                            step = -distanceThreshold
                        }
                        var counter:Int = 0
                        while ((lastReportedDistance + step - distanceFeet).sign == (lastReportedDistance - distanceFeet).sign) {
                            lastReportedDistance += step
                            counter += 1
                            if (counter > 1000) {
                                print("Infinite loop detected!")
                                break
                            }
                        }
                        var str = String(format:"%d feet", Int(lastReportedDistance))
                        speak(str:str)
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
