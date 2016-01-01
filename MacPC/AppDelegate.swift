//
//  AppDelegate.swift
//  MacPC
//
//  Created by Hamilton Chapman on 30/12/2015.
//  Copyright © 2015 Hamilton Chapman. All rights reserved.
//

import Cocoa
import CoreData

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(-2)
    let clicksMenuItem: NSMenuItem = NSMenuItem()
    let pressesMenuItem: NSMenuItem = NSMenuItem()
    let menu: NSMenu = NSMenu()
    
    @IBOutlet weak var window: NSWindow!

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarButtonImage")
        }
        
        setMenuItems()
        setupMenu()
        setupLogging()
    }
    
    func setMenuItems() {
        var clickTotal = 0
        var pressTotal = 0
        if let clicksToday = fetchTodaysTotalIfPresent("mouse") {
            clickTotal = clicksToday
        }
        if let pressesToday = fetchTodaysTotalIfPresent("key") {
            pressTotal = pressesToday
        }
        clicksMenuItem.title = "Clicks today: \(clickTotal)"
        pressesMenuItem.title = "Key presses today: \(pressTotal)"
    }
    
    func resync(sender: AnyObject) {
        print("About to resync")
    }
    
    func setupLogging() {
        if acquirePrivileges() {
            print("Accessibility Enabled")
            setupMasks()
        }
        else {
            print("Accessibility Disabled")
        }
    }
    
    func setupMasks() {
        NSEvent.addGlobalMonitorForEventsMatchingMask(.LeftMouseDownMask, handler: { event in
            print("Left mouse click")
            self.incrementOrCreate("mouse")
        })
        
        NSEvent.addGlobalMonitorForEventsMatchingMask(.RightMouseDownMask, handler: { event in
            print("Right mouse click")
            self.incrementOrCreate("mouse")
        })
        
        NSEvent.addGlobalMonitorForEventsMatchingMask(.KeyDownMask, handler: { event in
            print("Key press char:\(event.characters) key code: \(event.keyCode)")
            self.incrementOrCreate("key")
        })
    }
    
    func setupMenu() {
        menu.addItem(clicksMenuItem)
        menu.addItem(pressesMenuItem)
        menu.addItem(NSMenuItem(title: "Resync", action: Selector("resync:"), keyEquivalent: "R"))
        menu.addItem(NSMenuItem.separatorItem())
        menu.addItem(NSMenuItem(title: "Quit", action: Selector("terminate:"), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    func todaysDateAsString() -> String {
        let todaysDate = NSDate()
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.stringFromDate(todaysDate)
    }
    
    func fetchTodaysObjectIfPresent(type: String) -> NSManagedObject? {
        let managedContext = self.managedObjectContext
        let dateString = todaysDateAsString()
        
        let fetchRequest = NSFetchRequest(entityName: "DayTotal")
        fetchRequest.predicate = NSPredicate(format: "createdAt = %@ AND type = %@", dateString, type)
        
        // maybe store todays managed object id in variable
        
        do {
            if let results = try managedContext.executeFetchRequest(fetchRequest) as? [NSManagedObject] {
                if results.count == 1 {
                    return results[0]
                }
            }
        } catch {
            // handle error properly and add to counter and then change icon if too many errors, or post notification
            print("Error")
        }
        return nil
    }
    
    func fetchTodaysTotalIfPresent(type: String) -> Int? {
        if let todaysObject = fetchTodaysObjectIfPresent(type) {
            return todaysObject.valueForKey("total") as? Int
        }
        return nil
    }
    
    func incrementOrCreate(type: String) {
        let managedContext = self.managedObjectContext
        let dateString = todaysDateAsString()
        var newTotal: Int
        
        if let todaysObject = fetchTodaysObjectIfPresent(type) {
            let currentTotal = todaysObject.valueForKey("total") as! Int
            newTotal = currentTotal + 1
            todaysObject.setValue(newTotal, forKey: "total")
        } else {
            let entity =  NSEntityDescription.entityForName("DayTotal", inManagedObjectContext: managedContext)
            let dayTotal = NSManagedObject(entity: entity!, insertIntoManagedObjectContext: managedContext)
            dayTotal.setValue(dateString, forKey: "createdAt")
            dayTotal.setValue(type, forKey: "type")
            newTotal = 1
        }
        
        try! managedContext.save()
        updateMenuTitle(type, value: newTotal)
    }
    
    func updateMenuTitle(type: String, value: Int) {
        if type == "key" {
            pressesMenuItem.title = "Key presses today: \(value)"
        } else if type == "mouse" {
            clicksMenuItem.title = "Clicks today: \(value)"
        }
    }
    
    func acquirePrivileges() -> Bool {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let privOptions = [trusted as NSString: true]
        var accessEnabled = AXIsProcessTrustedWithOptions(privOptions)
        
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = "Enable MacPC"
            alert.informativeText = "Once you have enabled MacPC in System Preferences, click OK."
            alert.beginSheetModalForWindow(self.window, completionHandler: { response in
                if AXIsProcessTrustedWithOptions(privOptions) {
                    accessEnabled = true
                } else {
                    NSApp.terminate(self)
                }
            })
        }
        return accessEnabled
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }

    // MARK: - Core Data stack

    lazy var applicationDocumentsDirectory: NSURL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "gg.hc.MacPC" in the user's Application Support directory.
        let urls = NSFileManager.defaultManager().URLsForDirectory(.ApplicationSupportDirectory, inDomains: .UserDomainMask)
        let appSupportURL = urls[urls.count - 1]
        return appSupportURL.URLByAppendingPathComponent("gg.hc.MacPC")
    }()

    lazy var managedObjectModel: NSManagedObjectModel = {
        // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
        let modelURL = NSBundle.mainBundle().URLForResource("MacPC", withExtension: "momd")!
        return NSManagedObjectModel(contentsOfURL: modelURL)!
    }()

    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it. (The directory for the store is created, if necessary.) This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
        let fileManager = NSFileManager.defaultManager()
        var failError: NSError? = nil
        var shouldFail = false
        var failureReason = "There was an error creating or loading the application's saved data."

        // Make sure the application files directory is there
        do {
            let properties = try self.applicationDocumentsDirectory.resourceValuesForKeys([NSURLIsDirectoryKey])
            if !properties[NSURLIsDirectoryKey]!.boolValue {
                failureReason = "Expected a folder to store application data, found a file \(self.applicationDocumentsDirectory.path)."
                shouldFail = true
            }
        } catch  {
            let nserror = error as NSError
            if nserror.code == NSFileReadNoSuchFileError {
                do {
                    try fileManager.createDirectoryAtPath(self.applicationDocumentsDirectory.path!, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    failError = nserror
                }
            } else {
                failError = nserror
            }
        }
        
        // Create the coordinator and store
        var coordinator: NSPersistentStoreCoordinator? = nil
        if failError == nil {
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
            let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("CocoaAppCD.storedata")
            do {
                try coordinator!.addPersistentStoreWithType(NSXMLStoreType, configuration: nil, URL: url, options: nil)
            } catch {
                failError = error as NSError
            }
        }
        
        if shouldFail || (failError != nil) {
            // Report any error we got.
            var dict = [String: AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            if failError != nil {
                dict[NSUnderlyingErrorKey] = failError
            }
            let error = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            NSApplication.sharedApplication().presentError(error)
            abort()
        } else {
            return coordinator!
        }
    }()

    lazy var managedObjectContext: NSManagedObjectContext = {
        // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
        let coordinator = self.persistentStoreCoordinator
        var managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
    }()

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(sender: AnyObject!) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        if !managedObjectContext.commitEditing() {
            NSLog("\(NSStringFromClass(self.dynamicType)) unable to commit editing before saving")
        }
        if managedObjectContext.hasChanges {
            do {
                try managedObjectContext.save()
            } catch {
                let nserror = error as NSError
                NSApplication.sharedApplication().presentError(nserror)
            }
        }
    }

    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return managedObjectContext.undoManager
    }

    func applicationShouldTerminate(sender: NSApplication) -> NSApplicationTerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        
        if !managedObjectContext.commitEditing() {
            NSLog("\(NSStringFromClass(self.dynamicType)) unable to commit editing to terminate")
            return .TerminateCancel
        }
        
        if !managedObjectContext.hasChanges {
            return .TerminateNow
        }
        
        do {
            try managedObjectContext.save()
        } catch {
            let nserror = error as NSError
            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .TerminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButtonWithTitle(quitButton)
            alert.addButtonWithTitle(cancelButton)
            
            let answer = alert.runModal()
            if answer == NSAlertFirstButtonReturn {
                return .TerminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .TerminateNow
    }

}

