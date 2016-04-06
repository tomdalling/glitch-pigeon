//
//  AppDelegate.swift
//  Glitch Pigeon
//
//  Created by Tom on 5/04/2016.
//  Copyright © 2016 Tom Dalling. All rights reserved.
//

import Cocoa

let MaxHeaderSize = 2_000_000 // 2 Mb
let HeaderSliderExponent = 4.0

protocol Glitch {
    func title() -> String
    func glitch(data: NSMutableData)
}

struct BitFlipperGlitch: Glitch {
    let probability: Double

    func title() -> String {
        let p = probability * 100.0
        return "Bit Flipper \(p)%"
    }

    func glitch(data: NSMutableData) {
        let bytes = UnsafeMutablePointer<UInt8>(data.mutableBytes)

        for idx in 0..<data.length {
            let roll = Double(arc4random()) / Double(UINT32_MAX)
            if roll < probability {
                let bit: UInt32 = arc4random() % UInt32(8)
                let mask: UInt8 = (UInt8(1) << UInt8(bit))
                let b = bytes[idx]
                //           flipped bit | everything except flipped bit
                bytes[idx] = (mask & ~b) | (~mask & b)
            }
        }
    }
}

struct AdditionGlitch: Glitch {
    let operand: UInt8

    func title() -> String {
        return "Addition \(operand)"
    }

    func glitch(data: NSMutableData) {
        let bytes = UnsafeMutablePointer<UInt8>(data.mutableBytes)
        for idx in 0..<data.length {
            let result = UInt8.addWithOverflow(bytes[idx], operand)
            bytes[idx] = result.0
        }
    }
}

struct MonkeyGlitch: Glitch {
    let rampages: Int

    func title() -> String {
        return "Monkey Rampage x\(rampages)"
    }

    func glitch(data: NSMutableData) {
        let bytes = UnsafeMutablePointer<UInt8>(data.mutableBytes)
        for _ in 1...rampages {
            let idx = Int(arc4random()) % data.length
            bytes[idx] = ~bytes[idx]
        }
    }
}

struct NeighbourXor: Glitch {
    let distance: Int

    func title() -> String {
        return "Neighbour XOR \(distance)"
    }

    func glitch(data: NSMutableData) {
        let originalData = NSData(data: data)
        let originalBytes = UnsafePointer<UInt8>(originalData.bytes)
        let bytes = UnsafeMutablePointer<UInt8>(data.mutableBytes)
        let len = data.length
        for idx in 0..<len {
            let minIdx = max(0, idx - distance)
            let maxIdx = min(len-1, idx + distance)
            var b = UInt8(0)
            for distIdx in minIdx...maxIdx {
                b ^= originalBytes[distIdx]
            }
            bytes[idx] = b
        }
    }
}

struct BitShiftGlitch: Glitch {
    func title() -> String {
        return "Bit Shift"
    }

    func glitch(data: NSMutableData) {
        let bytes = UnsafeMutablePointer<UInt8>(data.mutableBytes)
        for idx in 0..<data.length {
            let b = bytes[idx]
            bytes[idx] = (b << 1) | (b >> 7)
        }
    }
}

struct Model {
    var inputURL: NSURL?
    var headerSize: Int
    var glitchIndex: Int
}

@NSApplicationMain
class AppDelegate: NSObject {
    var model: Model
    let glitches: [Glitch]

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var inputFileButton: NSButton!
    @IBOutlet weak var headerSizeSlider: NSSlider!
    @IBOutlet weak var headerSizeLabel: NSTextField!
    @IBOutlet weak var glitchTypePopup: NSPopUpButton!
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var openButton: NSButton!
    @IBOutlet weak var resetButton: NSButton!
    @IBOutlet weak var glitchButton: NSButton!

    override init() {
        model = Model(inputURL: nil, headerSize: 0, glitchIndex: 0)
        glitches = [
            BitFlipperGlitch(probability: 0.001),
            BitFlipperGlitch(probability: 0.01),
            BitFlipperGlitch(probability: 0.1),
            BitFlipperGlitch(probability: 0.5),
            BitFlipperGlitch(probability: 0.9),
            MonkeyGlitch(rampages: 1),
            MonkeyGlitch(rampages: 5),
            MonkeyGlitch(rampages: 20),
            MonkeyGlitch(rampages: 80),
            MonkeyGlitch(rampages: 200),
            AdditionGlitch(operand: 1),
            AdditionGlitch(operand: 32),
            AdditionGlitch(operand: 128),
            NeighbourXor(distance: 1),
            NeighbourXor(distance: 3),
            NeighbourXor(distance: 7),
            NeighbourXor(distance: 20),
            NeighbourXor(distance: 50),
            BitShiftGlitch(),
        ]
    }

    @IBAction func chooseFile(sender: AnyObject) {
        let op = NSOpenPanel()
        op.canChooseFiles = true
        op.canChooseDirectories = false
        op.resolvesAliases = false
        op.allowsMultipleSelection = false
        op.beginSheetModalForWindow(window) { result in
            if result == NSFileHandlingPanelOKButton {
                self.model.inputURL = op.URL!
                self.updateView()
            }
        }
    }

    @IBAction func glitch(sender: AnyObject) {
        let headerRange = NSMakeRange(0, model.headerSize)
        let buffer = NSMutableData(contentsOfURL: existingScratchOrOriginalURL())!
        let header = buffer.subdataWithRange(headerRange)
        let glitch = glitches[model.glitchIndex]

        buffer.replaceBytesInRange(headerRange, withBytes: nil, length: 0)
        glitch.glitch(buffer)
        buffer.replaceBytesInRange(NSMakeRange(0, 0), withBytes:header.bytes, length: header.length)

        buffer.writeToURL(scratchURL(), atomically: true)

        updateView()
    }

    @IBAction func open(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(existingScratchOrOriginalURL())
    }

    @IBAction func saveGlitch(sender: AnyObject) {
        var idx = 0
        while true {
            idx += 1
            let num = String(format: "%03d", idx)
            let saveURL = alternateInputURL("save_\(num)")
            if !URLExists(saveURL) {
                _ = try? NSFileManager.defaultManager().copyItemAtURL(scratchURL(), toURL: saveURL);
                return;
            }
        }
    }

    @IBAction func reset(sender: AnyObject) {
        let fm = NSFileManager.defaultManager()
        let scratch = scratchURL().path!
        if fm.fileExistsAtPath(scratch) {
            _ = try? fm.removeItemAtPath(scratch)
        }

        updateView()
    }

    @IBAction func updateModel(sender: AnyObject) {
        let factor = pow(headerSizeSlider.doubleValue, HeaderSliderExponent)
        model.headerSize = Int(Double(MaxHeaderSize) * factor)
        model.glitchIndex = glitchTypePopup.indexOfSelectedItem
        updateView()
    }

    func updateView() {
        if let inputURL = model.inputURL {
            inputFileButton.title = inputURL.lastPathComponent!
        } else {
            inputFileButton.title = "Choose File"
        }

        headerSizeSlider.doubleValue = pow(Double(model.headerSize) / Double(MaxHeaderSize), 1.0/HeaderSliderExponent)
        headerSizeLabel.integerValue = model.headerSize
        glitchTypePopup.selectItemAtIndex(model.glitchIndex)

        let hasInput = (model.inputURL != nil)
        let hasScratch = hasInput && URLExists(scratchURL())

        glitchButton.enabled = hasInput
        openButton.enabled = hasInput
        resetButton.enabled = hasScratch
        saveButton.enabled = hasScratch
    }

    func initGlitchTypePopup() {
        let menu = NSMenu()
        for glitch in glitches {
            menu.addItemWithTitle(glitch.title(), action: nil, keyEquivalent: "")
        }
        glitchTypePopup.menu = menu
    }

    func scratchURL() -> NSURL {
        return alternateInputURL("glitched")
    }

    func alternateInputURL(suffix: String) -> NSURL {
        let original = model.inputURL!
        let dir = original.URLByDeletingLastPathComponent!
        let ext = original.pathExtension
        var base = original.lastPathComponent!

        if ext != nil {
            let periodIdx = base.startIndex.advancedBy(base.characters.count - ext!.characters.count - 1)
            base = base.substringToIndex(periodIdx)
        }

        var newFilename = base + "." + suffix
        if ext != nil {
            newFilename = newFilename + "." + ext!
        }

        return NSURL(fileURLWithPath: newFilename, relativeToURL: dir).absoluteURL
    }

    func existingScratchOrOriginalURL() -> NSURL {
        let scratch = scratchURL()
        if URLExists(scratch){
            return scratch;
        } else {
            return model.inputURL!
        }
    }

    func saveUserDefaults() {
        let ud = NSUserDefaults.standardUserDefaults()

        ud.setURL(model.inputURL, forKey: "inputURL")
        ud.setInteger(model.headerSize, forKey: "headerSize")
        ud.setInteger(model.glitchIndex, forKey: "glitchIndex")

        ud.synchronize()
    }

    func loadUserDefaults() {
        let ud = NSUserDefaults.standardUserDefaults()

        model.inputURL = ud.URLForKey("inputURL")
        if model.inputURL != nil && !URLExists(model.inputURL!){
            model.inputURL = nil
        }

        if ud.objectForKey("headerSize") != nil {
            model.headerSize = ud.integerForKey("headerSize")
        }

        if ud.objectForKey("glitchIndex") != nil {
            model.glitchIndex = ud.integerForKey("glitchIndex")
        }
    }

    func URLExists(url: NSURL) -> Bool {
        return NSFileManager.defaultManager().fileExistsAtPath(url.path!);
    }
}

extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        initGlitchTypePopup()
        loadUserDefaults();
        updateView()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(notification: NSNotification) {
        saveUserDefaults();
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(notification: NSNotification) {
        NSApp.terminate(nil)
    }
}
