//
//  ListViewController.swift
//  ClassicPhotos
//
//  Created by Richard Turton on 03/07/2014.
//  Copyright (c) 2014 raywenderlich. All rights reserved.
//

import UIKit
import CoreImage

let dataSourceURL = NSURL(string:"http://www.raywenderlich.com/downloads/ClassicPhotosDictionary.plist")

class ListViewController: UITableViewController {

    var photos = [PhotoRecord]()
    let pendingOperations = PendingOperations()
    
    //MARK: - TableView DataSource
    
    override func tableView(tableView: UITableView?, numberOfRowsInSection section: Int) -> Int {
        return photos.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCellWithIdentifier("CellIdentifier", forIndexPath: indexPath)
        
        if cell.accessoryView == nil {
            let indicator = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
            cell.accessoryView = indicator
        }
        
        let indicator = cell.accessoryView as! UIActivityIndicatorView
        
        let photoDetails = photos[indexPath.row]
        
        cell.textLabel?.text = photoDetails.name
        cell.imageView?.image = photoDetails.image
        
        switch photoDetails.state {
        case .Filtered:
            indicator.stopAnimating()
        case .Failed:
            indicator.stopAnimating()
            cell.textLabel?.text = "Failed to load"
        case .New, .Downloaded:
            indicator.startAnimating()
            
            if (!tableView.dragging && !tableView.decelerating) {
                self.startOperationsForPhotoRecord(photoDetails,indexPath:indexPath)
            }
        }
        return cell
    }
    
    //MARK: - ScrollView Delegate
    
    override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        suspendAllOperations()
    }
    
    
    override func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            loadImagesForOnscreenCells()
            resumeAllOperations()
        }
    }
    
    override func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        loadImagesForOnscreenCells()
        resumeAllOperations()
    }

    
    //MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Classic Photos"
        fetchPhotoDetails()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    //MARK: - Private methods
    
    func startOperationsForPhotoRecord(photoDetails:PhotoRecord, indexPath:NSIndexPath) {
        
        
        let downloader = ImageDownloader(photoRecord: photoDetails)
        let filtration = ImageFiltration(photoRecord:photoDetails)
        
        switch (photoDetails.state) {
            
        case .New:
            filtration.addDependency(downloader)
            startDownloadOp(downloader, photoRecordAtIndexPath: indexPath)
            
        case .Downloaded:
            startFiltrationOp(filtration, photoRecordAtIndexPath: indexPath)
        default:
            NSLog("Do nothing")
        }
    }
    
    func startDownloadOp(downloadOp:ImageDownloader, photoRecordAtIndexPath:NSIndexPath) {
        if let _ = pendingOperations.downloadsInProgress[photoRecordAtIndexPath] {
            return
        }
        
        let downloader = downloadOp
        
        
        downloader.completionBlock = {
            if downloader.cancelled {
                return
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                self.pendingOperations.downloadsInProgress.removeValueForKey(photoRecordAtIndexPath)
                self.tableView.reloadRowsAtIndexPaths([photoRecordAtIndexPath], withRowAnimation: .Fade)
            })
        }
        
        pendingOperations.downloadsInProgress[photoRecordAtIndexPath] = downloader
        
        pendingOperations.downloadQueue.addOperation(downloader)
        
    }
    
    func startFiltrationOp(filtrationOP:ImageFiltration, photoRecordAtIndexPath:NSIndexPath) {
        if let _ = pendingOperations.filtrationsInProgress[photoRecordAtIndexPath] {
            return
        }
        
        let filterer = filtrationOP
        filterer.completionBlock = {
            if filterer.cancelled {
                return
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                self.pendingOperations.filtrationsInProgress.removeValueForKey(photoRecordAtIndexPath)
                self.tableView.reloadRowsAtIndexPaths([photoRecordAtIndexPath], withRowAnimation: .Fade)
            })
        }
        
        pendingOperations.filtrationsInProgress[photoRecordAtIndexPath] = filterer
        pendingOperations.filtrationQueue.addOperation(filterer)
        
    }
    
    func suspendAllOperations() {
        pendingOperations.downloadQueue.suspended = true
        pendingOperations.filtrationQueue.suspended = true
    }
    
    func resumeAllOperations() {
        pendingOperations.downloadQueue.suspended = false
        pendingOperations.filtrationQueue.suspended = false
    }
    
    
    func fetchPhotoDetails() {
        let request = NSURLRequest(URL: dataSourceURL!)
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        
        NSURLConnection.sendAsynchronousRequest(request, queue: NSOperationQueue.mainQueue()) { (response, data, error) in
            
            if data != nil {
                
                let datasourceDictionary = (try! NSPropertyListSerialization.propertyListWithData(data!, options: NSPropertyListMutabilityOptions.MutableContainersAndLeaves, format: nil)) as! NSDictionary
                
                for(key, value) in datasourceDictionary {
                    let name = key as? String
                    let url = NSURL(string: String (value))
                    
                    if name != nil && url != nil {
                        let photoRecord = PhotoRecord(name: name!, url: url!)
                        self.photos.append(photoRecord)
                    }
                }
                
                self.tableView.reloadData()
            }
            
            if error != nil {
                let alert = UIAlertView (title: "Oops", message: error!.localizedDescription, delegate: nil, cancelButtonTitle: "Ok")
                alert.show()
            }
            
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
        }
    }
    
    
    func loadImagesForOnscreenCells() {
        
        if let pathsArray = tableView.indexPathsForVisibleRows {
            var allPendingOperations = Set(pendingOperations.downloadsInProgress.keys)
            allPendingOperations.unionInPlace(pendingOperations.filtrationsInProgress.keys)
            
            var toBeCancelled = allPendingOperations
            let visiblePaths = Set(pathsArray)
            toBeCancelled.subtractInPlace(visiblePaths)
            
            var toBeStarted = visiblePaths
            toBeStarted.subtract(allPendingOperations)
            
            for indexPath in toBeCancelled {
                if let pendingDownload = pendingOperations.downloadsInProgress[indexPath] {
                    pendingDownload.cancel()
                }
                
                pendingOperations.downloadsInProgress.removeValueForKey(indexPath)
                if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath]{
                    pendingFiltration.cancel()
                }
                
                pendingOperations.filtrationsInProgress.removeValueForKey(indexPath)
            }
            
            for indexPath in toBeStarted {
                let indexPath = indexPath as NSIndexPath
                let recordToProcess = self.photos[indexPath.row]
                startOperationsForPhotoRecord(recordToProcess, indexPath: indexPath)
            }
        }
    }
    
}
  
  
    
    
