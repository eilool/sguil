# $Id: qrylib.tcl,v 1.22 2005/01/20 20:02:28 shalligan Exp $ #
#
# QueryRequest is called thru various drop downs.
# It's job is to massage the data into the meat of 
# a WHERE statement, pass the info on to the QryBuilder
# and finally call DBQueryRequest or SsnQueryRequest.
#
proc QueryRequest { tableName queryType { incidentCat {NULL} } } {
    global CUR_SEL_PANE
    set timestamp [lindex [GetCurrentTimeStamp "1 week ago"] 0]
    if { $tableName == "event" } {
	if { $incidentCat == 0 } {
	    set whereTmp "WHERE $tableName.timestamp > '$timestamp' AND event.status = 0 AND "
	} else {
	    set whereTmp "WHERE $tableName.timestamp > '$timestamp' AND "
	}   
    } else {
	if { ( $queryType == "srcip" || $queryType == "dstip" || $queryType == "src2dst" ) && $incidentCat == 1 } {
	    if { $CUR_SEL_PANE(format) == "SSN" } {
		set selectedIndex [$CUR_SEL_PANE(name).startTimeFrame.list curselection]
		set starttime [clock scan "30 min ago" -base [clock scan [$CUR_SEL_PANE(name).startTimeFrame.list get $selectedIndex]]]
	    } else {
		set selectedIndex [$CUR_SEL_PANE(name).dateTimeFrame.list curselection]
		set starttime [clock scan "30 min ago" -base [clock scan [$CUR_SEL_PANE(name).dateTimeFrame.list get $selectedIndex]]]
	    }
	    set endtime [expr $starttime + 3600]
	    set tminus [clock format $starttime -f "%Y-%m-%d %T"]
	    set tplus [clock format $endtime -f "%Y-%m-%d %T"]
	    set whereTmp "WHERE $tableName.start_time > '$tminus' AND $tableName.start_time < '$tplus' AND "
	} else {
	    set whereTmp "WHERE $tableName.start_time > '$timestamp' AND "
	}  
    }
    if { $queryType == "srcip" } {
	set selectedIndex [$CUR_SEL_PANE(name).srcIPFrame.list curselection]
	set srcIP [$CUR_SEL_PANE(name).srcIPFrame.list get $selectedIndex]
	set whereTmp "$whereTmp ($tableName.src_ip = INET_ATON('$srcIP') OR $tableName.dst_ip = INET_ATON('$srcIP'))"
    } elseif { $queryType == "srcport" } {
	set selectedIndex [$CUR_SEL_PANE(name).srcPortFrame.list curselection]
	set srcport [$CUR_SEL_PANE(name).srcPortFrame.list get $selectedIndex]
	set whereTmp "$whereTmp ($tableName.src_port = '$srcport' OR $tableName.dst_port = '$srcport')"
    } elseif { $queryType == "dstport" } {
	set selectedIndex [$CUR_SEL_PANE(name).dstPortFrame.list curselection]
	set dstport [$CUR_SEL_PANE(name).dstPortFrame.list get $selectedIndex]
	set whereTmp "$whereTmp ($tableName.src_port = '$dstport' OR $tableName.dst_port = '$dstport')"
    } elseif { $queryType == "dstip" } {
	set selectedIndex [$CUR_SEL_PANE(name).srcIPFrame.list curselection]
	set dstIP [$CUR_SEL_PANE(name).dstIPFrame.list get $selectedIndex]
	set whereTmp "$whereTmp ($tableName.src_ip  = INET_ATON('$dstIP') OR $tableName.dst_ip = INET_ATON('$dstIP'))"
    } elseif { $queryType == "empty" } {
	set whereTmp "$whereTmp <Insert Query Here>"
    } elseif { $queryType == "src2dst" } {
	set selectedIndex [$CUR_SEL_PANE(name).srcIPFrame.list curselection]
	set srcIP [$CUR_SEL_PANE(name).srcIPFrame.list get $selectedIndex]
	set dstIP [$CUR_SEL_PANE(name).dstIPFrame.list get $selectedIndex]
	set whereTmp "$whereTmp $tableName.src_ip  = INET_ATON('$srcIP') AND $tableName.dst_ip = INET_ATON('$dstIP')"
    } elseif { $queryType == "category" } {
	set whereTmp "$whereTmp event.status = $incidentCat"
    } elseif { $queryType == "signature" } {
	set selectedIndex [$CUR_SEL_PANE(name).srcIPFrame.list curselection]
	set eventMsg [$CUR_SEL_PANE(name).msgFrame.list get $selectedIndex]
	set whereTmp "$whereTmp event.signature = '$eventMsg'"
    }
    set tmpWhereStatement [QryBuild $tableName $whereTmp]
    set whereStatement [lindex $tmpWhereStatement 1]
    set tableName [lindex $tmpWhereStatement 0]
    if { $whereStatement == "cancel" } { return }
    if { $tableName == "event" } {
	if { $queryType == "category" } {
	    switch -exact $incidentCat {
		11 { set winTitle "Cat I" }
		12 { set winTitle "Cat II" }
		13 { set winTitle "Cat III" }
		14 { set winTitle "Cat IV" }
		15 { set winTitle "Cat V" }
		16 { set winTitle "Cat VI" }
		17 { set winTitle "Cat VII" }
		default { set winTitle "none" }
	    }
	    DBQueryRequest $whereStatement $winTitle
	} else {
	    DBQueryRequest $whereStatement
	}
    } elseif { $tableName == "sessions" } {
	SsnQueryRequest $whereStatement
    } elseif { $tableName == "sancp" } {
	SancpQueryRequest $whereStatement
    }
}
#
# Build a ssn query tab and send the query to sguild.
#
proc SsnQueryRequest { whereStatement } {
  global eventTabs SSN_QUERY_NUMBER socketID DEBUG
  global CONNECTED
  if {!$CONNECTED} {ErrorMessage "Not connected to sguild. Query aborted"; return}
  set selectQuery "SELECT sensor.hostname, sessions.xid, sessions.start_time, sessions.end_time,\
   INET_NTOA(sessions.src_ip), sessions.src_port, INET_NTOA(sessions.dst_ip), sessions.dst_port,\
   sessions.ip_proto, sessions.src_pckts, sessions.src_bytes, sessions.dst_pckts, sessions.dst_bytes\
   FROM sessions INNER JOIN sensor ON sessions.sid=sensor.sid $whereStatement"
  regsub -all {\n} $selectQuery {} selectQuery
  incr SSN_QUERY_NUMBER
  $eventTabs add -label "Ssn Query $SSN_QUERY_NUMBER"
  set currentTab [$eventTabs childsite end]
  set tabIndex [$eventTabs index end]
  set queryFrame [frame $currentTab.ssnquery_${SSN_QUERY_NUMBER} -background black -borderwidth 1]
  $eventTabs select end
  # Here is where we build the session display lists.
  CreateSessionLists sessions $queryFrame
  set buttonFrame [frame $currentTab.buttonFrame]
  set whereText [text $buttonFrame.text -height 1 -background white -wrap none]
  $whereText insert 0.0 $whereStatement
  bind $whereText <Return> {
    set whereStatement [%W get 0.0 end]
    SsnQueryRequest $whereStatement
    break
  }
  set closeButton [button $buttonFrame.close -text "Close" \
	  -relief raised -borderwidth 2 -pady 0 \
	  -command "DeleteTab $eventTabs $currentTab"]
  set exportButton [button $buttonFrame.export -text "Export" \
	  -relief raised -borderwidth 2 -pady 0 \
	  -command "ExportResults $queryFrame ssn"]
  set rsubmitButton [button $buttonFrame.rsubmit -text "Submit " \
	  -relief raised -borderwidth 2 -pady 0 \
	  -command "SsnQueryRequest \[$whereText get 0.0 end\] "]
  pack $closeButton $exportButton -side left
  pack $whereText -side left -fill x -expand true
  pack $rsubmitButton -side left
  pack $buttonFrame -side top -fill x
  pack $queryFrame -side bottom -fill both
  $queryFrame configure -cursor watch
  if {$DEBUG} { puts "Sending Server: QueryDB $queryFrame $selectQuery" }
  SendToSguild "QueryDB $queryFrame $selectQuery"
}
#
# Build an event query tab and send the query to sguild.
#
proc DBQueryRequest { whereStatement {winTitle {none} } } {
  global eventTabs QUERY_NUMBER socketID DEBUG
  global CONNECTED
  if {!$CONNECTED} {ErrorMessage "Not connected to sguild. Query aborted."; return}
  
  set selectQuery "SELECT event.status, event.priority, sensor.hostname, event.timestamp,\
   event.sid, event.cid, event.signature,\
   INET_NTOA(event.src_ip), INET_NTOA(event.dst_ip), event.ip_proto,\
   event.src_port, event.dst_port"
  # Parse the WHERE and determine what tables we need to SELECT from.
  # We'll always have 'event' and 'sensor'.
  set fromQuery " FROM event INNER JOIN sensor ON event.sid=sensor.sid"
  if { [regexp {\s+user_info\.} $whereStatement] } {
    set fromQuery "$fromQuery INNER JOIN user_info ON user_info.uid=event.last_uid"
  }
  if { [regexp {\s+tcphdr\.} $whereStatement] } {
    set fromQuery "$fromQuery INNER JOIN tcphdr ON event.sid=tcphdr.sid AND event.cid=tcphdr.cid"
  }
  if { [regexp {\s+udphdr\.} $whereStatement] } {
    set fromQuery "$fromQuery INNER JOIN udphdr ON event.sid=udphdr.sid AND event.cid=udphdr.cid"
  }
  if { [regexp {\s+icmphdr\.} $whereStatement] } {
    set fromQuery "$fromQuery INNER JOIN icmphdr ON event.sid=icmphdr.sid AND event.cid=icmphdr.cid"
  }
  if { [regexp {\s+data\.} $whereStatement] } {
    set fromQuery "$fromQuery INNER JOIN data ON event.sid=data.sid AND event.cid=data.cid"
  }
  set selectQuery "$selectQuery $fromQuery $whereStatement"
  regsub -all {\n} $selectQuery {} selectQuery
  incr QUERY_NUMBER
  if { $winTitle == "none" } {
    $eventTabs add -label "Event Query $QUERY_NUMBER"
  } else {
    $eventTabs add -label "Event Query $winTitle"
  }
  set currentTab [$eventTabs childsite end]
  set tabIndex [$eventTabs index end]
  set queryFrame [frame $currentTab.query_$QUERY_NUMBER -background black -borderwidth 1]
  $eventTabs select end
  CreateEventLists $queryFrame
  set buttonFrame [frame $currentTab.buttonFrame]
  set whereText [text $buttonFrame.text -background white -height 1 -wrap none]
  $whereText insert 0.0 $whereStatement
  bind $whereText <Return> {
    set whereStatement [%W get 0.0 end]
    DBQueryRequest $whereStatement
    break
  }
  set closeButton [button $buttonFrame.close -text "Close" \
	  -relief raised -borderwidth 2 -pady 0 \
	  -command "DeleteTab $eventTabs $currentTab"]
  set exportButton [button $buttonFrame.export -text "Export " \
	  -relief raised -borderwidth 2 -pady 0 \
	  -command "ExportResults $queryFrame event"]
  set rsubmitButton [button $buttonFrame.rsubmit -text "Submit " \
	  -relief raised -borderwidth 2 -pady 0 \
	  -command "DBQueryRequest \[$whereText get 0.0 end\] "]
  pack $closeButton $exportButton -side left
  pack $whereText -side left -fill x -expand true
  pack $rsubmitButton  -side left
  pack $buttonFrame -side top -fill x
  pack $queryFrame -side bottom -fill both
  $queryFrame configure -cursor watch
  if {$DEBUG} { puts "Sending Server: QueryDB $queryFrame $selectQuery" }
  SendToSguild "QueryDB $queryFrame $selectQuery"
}
# Depreciated
proc GetStdQuery {} {
  set data [StdQuery]
  set  [lindex $data 0]
  if { $query == "abort" } { return }
  set whereStatement [EditWhere $query]
  if { $whereStatement == "cancel" } { return }
  if { [lindex $data 1] == "sessions" } {
    SsnQueryRequest $whereStatement
  } else {
    DBQueryRequest $whereStatement
  }
}
# Depreciated
proc EditWhere { whereTmp } {
  global RETURN_FLAG
  set RETURN_FLAG 0
  set editWhere .editWhere
  if { [winfo exists $editWhere] } {
    wm withdraw $editWhere
    wm deiconify $editWhere
    return
  }
  toplevel $editWhere
  wm geometry $editWhere +[expr [winfo pointerx .] - 200]+[expr [winfo pointery .]- 30 ]
  wm title $editWhere "Query Template"
  set textBox [scrolledtext $editWhere.textBox -textbackground white -vscrollmode dynamic\
   -hscrollmode none -wrap word -visibleitems 80x5 -labeltext "Edit WHERE Statement"]
  set buttonBox [buttonbox $editWhere.buttonBox]
    $buttonBox add ok -text "Ok" -command "set RETURN_FLAG 1"
    $buttonBox add showTables -text "Show DB Tables" -command ShowDBTables
    $buttonBox add cancel -text "Cancel" -command "set RETURN_FLAG 0"
  pack $textBox $buttonBox -side top -fill both -expand true
  set whereTmp "$whereTmp LIMIT 500"
  $textBox insert end "$whereTmp"
  tkwait variable RETURN_FLAG
  if {$RETURN_FLAG} {
    set whereStatement [$textBox get 0.0 end]
    regsub -all {\n} $whereStatement {} whereStatement
  } else {
    set whereStatement "cancel"
  }
  destroy $editWhere
  return $whereStatement
}
