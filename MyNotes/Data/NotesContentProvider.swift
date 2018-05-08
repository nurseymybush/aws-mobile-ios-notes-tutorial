/*
 * Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file
 * except in compliance with the License. A copy of the License is located at
 *
 *    http://aws.amazon.com/apache2.0/
 *
 * or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for
 * the specific language governing permissions and limitations under the License.
 */

import Foundation
import CoreData
import UIKit
import AWSCore
import AWSPinpoint

import AWSDynamoDB
import AWSAuthCore

// The content provider for the internal Note database (Core Data)

public class NotesContentProvider  {
    
    var myNotes: [NSManagedObject] = []
    let emptyTitle: String? = " "
    let emptyContent: String? = " "
    
    func getContext() -> NSManagedObjectContext {
        let managedContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        return managedContext
    }
    
    /**
     * Insert a new record into the database using NSManagedObjectContext
     *
     * @param noteTitle the note title to be inserted
     * @param noteContent the note content to be inserted
     * @return noteId the unique Note Id
     */
    func insert(noteTitle: String, noteContent: String) -> String {
        
        // Get NSManagedObjectContext
        let managedContext = getContext()
        
        let entity = NSEntityDescription.entity(forEntityName: "Note",
                                                in: managedContext)!
        
        let myNote = NSManagedObject(entity: entity,
                                     insertInto: managedContext)
        
        // Set the Note Id
        let newNoteId = NSUUID().uuidString
        myNote.setValue(NSDate(), forKeyPath: "creationDate")
        print("New note being created: \(newNoteId)")
        
        myNote.setValue(newNoteId, forKeyPath: "noteId")
        myNote.setValue(noteTitle, forKeyPath: "title")
        myNote.setValue(noteContent, forKeyPath: "content")
        
        do {
            try managedContext.save()
            myNotes.append(myNote)
        } catch let error as NSError {
            print("Could not save note. \(error), \(error.userInfo)")
        }
        print("New Note Saved : \(newNoteId)")
        
        //Send AddNote analytics event
        sendNoteEvent(noteId: newNoteId, eventType: noteEventType.AddNote.rawValue)

        return newNoteId
    }
    
    /**
     * Update an existing Note using NSManagedObjectContext
     * @param noteId the unique identifier for this note
     * @param noteTitle the note title to be updated
     * @param noteContent the note content to be updated
     */
    func update(noteId: String, noteTitle: String, noteContent: String)  {
        
        // Get NSManagedObjectContext
        let managedContext = getContext()
        
        let entity = NSEntityDescription.entity(forEntityName: "Note",
                                                in: managedContext)!
        
        let myNote = NSManagedObject(entity: entity,
                                     insertInto: managedContext)
        
        myNote.setValue(noteId, forKeyPath: "noteId")
        myNote.setValue(noteTitle, forKeyPath: "title")
        myNote.setValue(noteContent, forKeyPath: "content")
        myNote.setValue(NSDate(), forKeyPath: "updatedDate")
        
        do {
            try managedContext.save()
            myNotes.append(myNote)
        } catch let error as NSError {
            print("Could not save note. \(error), \(error.userInfo)")
        }
        print("Updated note with NoteId: \(noteId)")
    }
    
    /**
     * Delete note using NSManagedObjectContext and NSManagedObject
     * @param managedObjectContext the managed context for the note to be deleted
     * @param managedObj the core data managed object for note to be deleted
     * @param noteId the noteId to be delete
     */
    public func delete(managedObjectContext: NSManagedObjectContext, managedObj: NSManagedObject, noteId: String!)  {
        let context = managedObjectContext
        context.delete(managedObj)
        
        do {
            try context.save()
            print("Deleted local NoteId: \(noteId)")
            // Send DeletNote analytics event
            sendNoteEvent(noteId: noteId, eventType: noteEventType.DeleteNote.rawValue)
        } catch {
            let nserror = error as NSError
            fatalError("Unresolved local delete error \(nserror), \(nserror.userInfo)")
        }
    }
    
    // Send analytics AddNote and DeleteNote events
    func sendNoteEvent(noteId: String, eventType: String)
    {
        
        let pinpointClient = AWSPinpoint(configuration:
            AWSPinpointConfiguration.defaultPinpointConfiguration(launchOptions: nil))
        
        let pinpointAnalyticsClient = pinpointClient.analyticsClient
        
        let event = pinpointAnalyticsClient.createEvent(withEventType: eventType)
        event.addAttribute("NoteId", forKey: noteId)
        pinpointAnalyticsClient.record(event)
        pinpointAnalyticsClient.submitEvents()
    }
    
    enum noteEventType: String {
        case AddNote = "AddNote"
        case DeleteNote = "DeleteNote"
    }
    
    //Insert a note using Amazon DynamoDB
    func insertNoteDDB(noteId: String, noteTitle: String, noteContent: String) -> String {
        
        let dynamoDbObjectMapper = AWSDynamoDBObjectMapper.default()
        
        // Create a Note object using data model you downloaded from Mobile Hub
        let noteItem: Notes = Notes()
        
        noteItem._userId = AWSIdentityManager.default().identityId
        noteItem._noteId = noteId
        noteItem._title = emptyTitle
        noteItem._content = emptyContent
        noteItem._creationDate = NSDate().timeIntervalSince1970 as NSNumber
        
        //Save a new item
        dynamoDbObjectMapper.save(noteItem, completionHandler: {
            (error: Error?) -> Void in
            
            if let error = error {
                print("Amazon DynamoDB Save Error on new note: \(error)")
                return
            }
            print("New note was saved to DDB.")
        })
        
        return noteItem._noteId!
    }
    
    //Insert a note using Amazon DynamoDB
    func updateNoteDDB(noteId: String, noteTitle: String, noteContent: String)  {
        
        let dynamoDbObjectMapper = AWSDynamoDBObjectMapper.default()
        
        let noteItem: Notes = Notes()
        
        noteItem._userId = AWSIdentityManager.default().identityId
        noteItem._noteId = noteId
        
        if (!noteTitle.isEmpty){
            noteItem._title = noteTitle
        } else {
            noteItem._title = emptyTitle
        }
        
        if (!noteContent.isEmpty){
            noteItem._content = noteContent
        } else {
            noteItem._content = emptyContent
        }
        
        noteItem._updatedDate = NSDate().timeIntervalSince1970 as NSNumber
        let updateMapperConfig = AWSDynamoDBObjectMapperConfiguration()
        updateMapperConfig.saveBehavior = .updateSkipNullAttributes //ignore any null value attributes and does not remove in database
        dynamoDbObjectMapper.save(noteItem, configuration: updateMapperConfig, completionHandler: {(error: Error?) -> Void in
            if let error = error {
                print(" Amazon DynamoDB Save Error on note update: \(error)")
                return
            }
            print("Existing note updated in DDB.")
        })
    }
    
    //Delete a note using Amazon DynamoDB
    func deleteNoteDDB(noteId: String) {
        let dynamoDbObjectMapper = AWSDynamoDBObjectMapper.default()
        
        let itemToDelete = Notes()
        itemToDelete?._userId = AWSIdentityManager.default().identityId
        itemToDelete?._noteId = noteId
        
        dynamoDbObjectMapper.remove(itemToDelete!, completionHandler: {(error: Error?) -> Void in
            if let error = error {
                print(" Amazon DynamoDB Save Error: \(error)")
                return
            }
            print("An note was deleted in DDB.")
        })
    }
    
    func getNotesFromDDB() {
        // 1) Configure the query looking for all the notes created by this user (userId => Cognito identityId)
        let queryExpression = AWSDynamoDBQueryExpression()
        
        queryExpression.keyConditionExpression = "#userId = :userId"
        
        queryExpression.expressionAttributeNames = [
            "#userId": "userId",
        ]
        queryExpression.expressionAttributeValues = [
            ":userId": AWSIdentityManager.default().identityId
        ]
        
        // 2) Make the query
        let dynamoDbObjectMapper = AWSDynamoDBObjectMapper.default()
        
        dynamoDbObjectMapper.query(Notes.self, expression: queryExpression) { (output: AWSDynamoDBPaginatedOutput?, error: Error?) in
            if error != nil {
                print("DynamoDB query request failed. Error: \(String(describing: error))")
            }
            if output != nil {
                print("Found [\(output!.items.count)] notes")
                for notes in output!.items {
                    let noteItem = notes as? Notes
                    print("\nNoteId: \(noteItem!._noteId!)\nTitle: \(noteItem!._title!)\nContent: \(noteItem!._content!)")
                }
            }
        }
    }
}
