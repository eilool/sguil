# $Id: SguildEvent.tcl,v 1.2 2004/10/18 15:28:20 shalligan Exp $ #

#
# EventRcvd: Called by main when events are received.
#
proc EventRcvd { socketID data } {
  global EMAIL_EVENTS EMAIL_CLASSES EMAIL_DISABLE_SIDS EMAIL_ENABLE_SIDS eventIDCountArray
  global acRules acCat correlatedEventArray eventIDList
  set eventDataList [lrange [split $data |] 1 15]
  if { [lindex $eventDataList 2] == "system-info" } {
    InfoMessage "SYSTEM INFO: $eventDataList"
    puts $socketID "CONFIRM system msg"
    set sensorName [lindex $eventDataList 3]
    set message [lindex $eventDataList 5]
    SendSystemInfoMsg $sensorName $message
  } else {
    InfoMessage "Alert Received: $eventDataList"
    puts $socketID "CONFIRM [lindex $eventDataList 6]"
    flush $socketID
    # Make sure we don't have a dupe. If so, report an error and return.
    set currentEventAID [join [lrange $eventDataList 4 5] .]
    if { [lsearch $eventIDList $currentEventAID] >= 0 } {
      # Have a dupe. Could be b/c we just initialized and a sensor
      # was waiting to send us an alert that we pulled from the DB.
      InfoMessage "Non-fatal Error: recieved a duplicate alert. : $currentEventAID"
      return
    }
    # If we don't have any auto-cat rules, or we don't match on
    # the autocat, then we send off the rule
    if { ![array exists acRules] || ![AutoCat $eventDataList] } {
      # Correlation/aggregation checks here: CorrelateEvent SrcIP Message
      set matchAID [ CorrelateEvent [lindex $eventDataList 8] [lindex $eventDataList 7] ]
      if { $matchAID == 0 } {
        AddEventToEventArray $eventDataList
        # Clients don't need the sid and rev
        SendEvent "[lrange $eventDataList 0 12] 1"
        if { $EMAIL_EVENTS } {
          #Ug-ly. Things will get better when the rules are in the DB.
          set sid [lindex $eventDataList 13]
          set class [lindex $eventDataList 2]
          if { ([lsearch -exact $EMAIL_CLASSES $class] >= 0\
               && [lsearch -exact $EMAIL_DISABLE_SIDS $sid] < 0)
               || [lsearch -exact $EMAIL_ENABLE_SIDS $sid] >= 0 } {
            EmailEvent $eventDataList
          }
        }
      } else {
        # Add event to parents list
        lappend correlatedEventArray($matchAID) $eventDataList
        # Bump the parents count
        incr eventIDCountArray($matchAID)
        # Send an update notice to clients
        set sensorName [lindex $eventDataList 3]
        SendIncrEvent $matchAID $sensorName $eventIDCountArray($matchAID) [lindex $eventDataList 1]
      }
    }
  }
}

#
# AddEventToEventArray: Global eventIDArray contains current events.
#
proc AddEventToEventArray { eventDataList } {
  global eventIDArray eventIDList sensorIDList eventIDCountArray
  set eventID [join [lrange $eventDataList 5 6] .]
  set eventIDCountArray($eventID) 1
  set sensorName [lindex $eventDataList 3]
  set eventIDArray($eventID) $eventDataList
  # Arrays are not kept in any particular order so we have to keep
  # a list in order to control the order the clients recieve events
  lappend eventIDList $eventID
}

proc DeleteEventIDList { socketID data } {
  global eventIDArray eventIDList clientList escalateArray escalateIDList
  global userIDArray correlatedEventArray eventIDCountArray
                                                                                                            
  regexp {^(.*)::(.*)::(.*)$} $data allMatch status comment eidList
  set updateTmp ""
  foreach socket $clientList {
    # Sending a DeleteEventID to the originating client allows us
    # to remove events from the RT panes when deleting from a query.
    # Problem is, we could delete a correlated event parent without
    # deleting the children thus leaving alerts that haven't been
    # dealt with.
    catch {SendSocket $socket "DeleteEventIDList $eidList"} tmpError
  }
                                                                                                            
  # First we need to split up the update based on uniques sids
  # because doing a WHERE sid=foo and cid IN (bar, blah) is
  # much faster than a bunch of ORs.
                                                                                                            
  foreach eventID $eidList {
                                                                                                            
    set tmpSid [lindex [split $eventID .] 0]
    set tmpCid [lindex [split $eventID .] 1]
    lappend tmpCidList($tmpSid) $tmpCid
                                                                                                            
    # Delete from the escalate list
    if { [info exists escalateIDList] } {set escalateIDList [ldelete $escalateIDList $eventID]}
                                                                                                            
    # tmp list of eids we are updating
    lappend tmpEidList $eventID
                                                                                                            
    # loop through the parents array and add all the sids/cids to the UPDATE
    if [info exists correlatedEventArray($eventID)] {
      foreach row $correlatedEventArray($eventID) {
        set tmpSid [lindex $row 5]
        set tmpCid [lindex $row 6]
        lappend tmpCidList($tmpSid) $tmpCid
                                                                                                            
        if { [info exists escalateIDList] } {
          set escalateIDList [ldelete $escalateIDList "$tmpSid.$tmpCid"]
        }
                                                                                                            
        # Tmp list of eids
        lappend tmpEidList "$tmpSid.$tmpCid"
      }
    }
  }
                                                                                                            
  # Unique out dupes
  set tmpEidList [lsort -unique $tmpEidList]
                                                                                                            
  # Number of events we should be updating
  set eidListSize [llength $tmpEidList]
  # Now we have a complete list of event IDs. Loop thru them and update our current VARs
  # and send escalate notices if needed
  foreach tmpEid $tmpEidList {
    # If status == 2 then escalate
    if {$status == 2} {
      lappend escalateIDList $tmpEid
      if [info exists eventIDArray($tmpEid)] {
        set escalateArray($tmpEid) $eventIDArray($tmpEid)
      } else {
        set escalateArray($tmpEid) [FlatDBQuery\
         "SELECT event.status, event.priority, event.class, sensor.hostname, event.timestamp, event.sid, event.cid, event.signature, INET_NTOA(event.src_ip), INET_NTOA(event.dst_ip), event.ip_proto, event.src_port, event.dst_port FROM event, sensor WHERE event.sid=sensor.sid AND event.sid=[lindex [split $tmpEid .] 0] AND event.cid=[lindex [split $tmpEid .] 1]"]
      }
      foreach socket $clientList {
        catch {SendSocket $socket "InsertEscalatedEvent $escalateArray($tmpEid)"} tmpError
      }
    }
    # Cleanup
    if { [info exists eventIDArray($tmpEid)] } { unset eventIDArray($tmpEid) }
    if { [info exists correlatedEventArray($tmpEid)] } { unset correlatedEventArray($tmpEid) }
    if { [info exists eventIDCountArray($tmpEid)] } { unset eventIDCountArray($tmpEid) }
    if [info exists eventIDList] {
      set eventIDList [ldelete $eventIDList $tmpEid]
    }
  }
                                                                                                            
  # Finally we update the event table.
  # Do an UPDATE for each unique sid
  set totalUpdates 0
  foreach uSid [array names tmpCidList] {
    # Make sure there are no duplicates
    set tmpCidList($uSid) [lsort -unique $tmpCidList($uSid)]
    # Build our WHERE
    set whereTmp "sid=$uSid AND cid IN ([join $tmpCidList($uSid) ,])"
    set tmpUpdated [UpdateDBStatusList $whereTmp [GetCurrentTimeStamp] $userIDArray($socketID) $status]
    set totalUpdates [expr $totalUpdates + $tmpUpdated]
  }
  # See if the number of rows updated matched the number of events we
  # meant to update
  if { $totalUpdates != $eidListSize } {
    catch {SendSocket $socketID "ErrorMessage ERROR: Some events may not have been updated. Event(s) may be missing from DB. See sguild output for more information."} tmpError
    LogMessage "ERROR: Number of updates mismatched number of events. \
	    Number of EVENTS:  $eidListSize \
	    Number of UPDATES: $totalUpdates Update List: $tmpEidList"
  } else {
    InfoMessage "Updated $totalUpdates event(s)."
  }
  # Update the history here
  foreach tmpEid $tmpEidList {
    set tmpSid [lindex [split $tmpEid .] 0]
    set tmpCid [lindex [split $tmpEid .] 1]
    InsertHistory $tmpSid $tmpCid $userIDArray($socketID) [GetCurrentTimeStamp] $status $comment
  }
}


proc DeleteEventID { socketID eventID status } {
  global eventIDArray eventIDList clientList escalateArray escalateIDList
  global userIDArray
                                                                                                            
  foreach socket $clientList {
    # See comments in DeleteEventIDList
    catch {SendSocket $socket "DeleteEventID $eventID"} tmpError
  }
  # If status == 2 then escalate
  if { $status == 2 } {
    lappend escalateIDList $eventID
    set escalateArray($eventID) $eventIDArray($eventID)
    foreach socket $clientList {
      catch {SendSocket $socket "InsertEscalatedEvent $escalateArray($eventID)"} tmpError
    }
  }
  if { [info exists escalateArray($eventID)] } { unset escalateArray($eventID) }
  if { [info exists escalateIDList] } {set escalateIDList [ldelete $escalateIDList $eventID]}
  if { [info exists eventIDArray($eventID)] } { unset eventIDArray($eventID) }
  set eventIDList [ldelete $eventIDList $eventID]
  InsertHistory [lindex [split $eventID .] 0] [lindex [split $eventID .] 1]\
   $userIDArray($socketID) [GetCurrentTimeStamp] $status
  UpdateDBStatus $eventID [GetCurrentTimeStamp] $userIDArray($socketID) $status
}

proc CorrelateEvent { srcip msg } {
  global eventIDArray eventIDList eventIDCountArray
  set MATCH 0
  # Loop thru the RTEVENTS for a match on srcip msg
  foreach rteid $eventIDList {
    if { [lindex $eventIDArray($rteid) 8] == $srcip && [lindex $eventIDArray($rteid) 7] == $msg } {
      # Have a match
      set MATCH $rteid
    }
  }
  return $MATCH
}








