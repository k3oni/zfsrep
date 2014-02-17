#!/sbin/sh
#
# Created: 09-15-09 Florian Neagu - michaelneagu@gmail.com - https://github.com/k3oni
# Updated: 01-30-13 Florian Neagu
#
# Description: Managed ZFS SYNC Replication/Snapshoting script
#              - Provides initial, manual and periodic sync-ing of zfs filesystems
#              - Manages snapshots on local and remote filesystem
#			      - Can snapshot from main to slave and restore from slave to main if available on both systems
#
# Options:     init: Create the initial snapshot and replication set
#              sync: Updates/syncs a replication set
#              start: Adds cron entry for periodic sync for a given filesystem
#              stop: Removes the cron entry for the given filesystem
#              reverse: Updates the last valid snapshot for the replication process from the current MAIN SAN/NAS
#
##################################################################################

scriptdir=""
emailalert=""
port=""


if [ "$1" != "init" -a "$1" != "sync" -a "$1" != "start" -a "$1" != "stop" -a "$1" != "reverse" ]; then
   echo "Usage: zfsrep.sh <start {filesystem destination remotehost interval}> | "
   echo "                 <stop> | "
   echo "                 <init {<filesystem> <destination> [remotehost]}> | "
   echo "                 <sync {<filesystem> <destination> [remotehost]}> | "
   echo "                 <reverse {<filesystem> <destination> [remotehost]}>"
   echo "                 Where: 'interval' is 1, 5 or 10 minutes. This will create a sync that will run every minute, every 5 minutes or every 10 minutes."
   echo ""
   echo "Examples:        zfsrep.sh init rpool/myfs drpool/myfs host2"
   echo "Version:         0.70"
   exit 1
fi

#START Functions

#Functions for crontab
crontab_add()
{
    # when (m h dom mon dow) command
    (crontab -l 2> /dev/null | grep -v -F "$2" ; echo "$@") | crontab
}
        
crontab_del()
{
    /usr/bin/crontab -l root | /usr/gnu/bin/grep -v "$1" | /usr/bin/crontab
    #(crontab -l 2> /dev/null | grep -v -F "$1") | crontab
}

comstar_lu()
{
    old_IFS=$IFS
    IFS=$'
    '
    lines=($(cat $scriptdir/COMSTAR)) # array
    echo ${lines[$@]}
    IFS=$old_IFS
}           
#END Functions

#---Check for required zfsrep.sh snapshot storage directory
if [ ! -d $scriptdir/zfsrep.snapshots ]; then
   mkdir $scriptdir/zfsrep.snapshots
fi


#---If given, make sure we can ping and ssh into the remote system
if [ "$4" != "" ]; then
   alive=`ping $4 2 | grep "^no answer"`
   if [ "$alive" != "" ]; then
      err="Error-Unable to ping the remote host: '$4'"
      echo "`date`  $err" >> $scriptdir/zfsrep.log
      if [ "$emailalert" != "" ]; then
         echo "zfsrep: $err" | mailx -s "zfsrep on `hostname`" $emailalert;    
      fi
      exit 1
   fi
fi


#---Get date/time stamp for new snapshots
DATE=`date '+%Y%m%d%H%M%S'`


#---Determine previous snapshot file
#ZFS=`echo $2 | awk '{FS="/"; print $1"-"$2}'`
ZFS=`echo $2 | sed 's/\//-/g'`
ZFSsnaplog="$scriptdir/zfsrep.snapshots/$ZFS.lastsnap"


#---Check to make sure the source and destination zfs filesystems exist
if [ "$1" != "reverse" ]; then
    zfschk=`zfs list $2 | grep "^$2"`
    if [ "$zfschk" = "" ]; then
        err="Error-Given source filesystem '$2' is not listed on local system, stopping automtic sync if running as something bad may have happened."
        echo "`date`  $err" >> $scriptdir/zfsrep.log
            if [ "$emailalert" != "" ]; then
            echo "zfsrep: $err" | mailx -p "high" -s "zfsrep on `hostname`" $emailalert;
            fi
        
        $scriptdir/zfsrep.sh stop
        exit 1
    fi
fi

if [ "$1" != "init" ]; then
   if [ "$4" != "" ]; then
      zfschk=`ssh $port $4 "zfs list $3 | grep '^$3'"`
      if [ "$zfschk" = "" ]; then
         err="Error-Given destination filesystem '$3' is not listed on the remote system, stopping automatic sync if running as something bad may have happened."
         echo "`date`  $err" >> $scriptdir/zfsrep.log
            if [ "$emailalert" != "" ]; then
                echo "zfsrep: $err" | mailx -p "high" -s "zfsrep on `hostname`" $emailalert;
            fi
         
         $scriptdir/zfsrep.sh stop
         exit 1
      fi
   else
      zfschk=`zfs list $3 | grep "^$3"`
      if [ "$zfschk" = "" ]; then
        err="Error-Given destination filesystem '$3' is not listed on this system, stopping automatic sync if running as something bad may have happened."
        echo "`date`  $err" >> $scriptdir/zfsrep.log
            if [ "$emailalert" != "" ]; then
                echo "zfsrep: $err" | mailx -p "high" -s "zfsrep on `hostname`" $emailalert;
            fi
        $scriptdir/zfsrep.sh stop
        exit 1 
      fi 
   fi 
fi 


#---Check to make sure the given option is ready to run and last snapshots exist 
if [ "$1" = "start" -o "$1" = "sync" ]; then
   if [ -f $ZFSsnaplog ]; then
      OLDsnap=`cat $ZFSsnaplog`
      zfschk=`zfs list $2@$OLDsnap | grep "^$2@$OLDsnap"`
      if [ "$zfschk" = "" ]; then
         echo "`date`  Error-Replication record exists, but the snapshot for the source filesystem does not exist. You may need to re"init"alize." >> $scriptdir/zfsrep.log
         exit 1
      fi

      if [ "$4" != "" ]; then
         zfschk=`ssh $port $4 "zfs list $3@$OLDsnap | grep '^$3@$OLDsnap'"`
         if [ "$zfschk" = "" ]; then
            echo "`date`  Error: The snapshot record exists but the snapshot itself doesn't exist on the destination." >> $scriptdir/zfsrep.log
            echo "`date`  You may need to re"init"alize the replication." >> $scriptdir/zfsrep.log
            exit 1
         fi
      else
         zfschk=`zfs list $3@$OLDsnap | grep "^$3@$OLDsnap"`
         if [ "$zfschk" = "" ]; then
            echo "`date`  Error: The snapshot record exists but the snapshot itself doesn't exist locally" >> $scriptdir/zfsrep.log
            echo "`date`  You may need to re"init"alize the replication." >> $scriptdir/zfsrep.log
            exit 1
         fi
      fi

   else
      echo "`date`  Not able to proceed. Replication doesn't appeared to have been initialized. Cannot find last snapshot record used for syncronized baseline." >> $scriptdir/zfsrep.log
      exit 1
   fi

fi


#---Make sure only one replication script is running to replicte to a single destination filesystem
tmp=`echo $3 | sed 's/\//-/g'`
destrun="$scriptdir/zfsrep.snapshots/$tmp.running"
if [ -f $destrun ]; then
   echo "Error:  zfsrep FLAG indicates that you are currently replicating to the given destination file system."
   echo "        If you are sure this is not the case, you can delete the flag file '$destrun' and try again."
   exit 1
else
   touch $destrun
fi


#---Case Statement
case "$1" in
'start')
        if [ "$5" = "5" ]; then
        crontab_add '0,5,10,15,20,25,30,35,40,45,50,55 * * * *' /opt/scripts/zfsrep.sh sync $2 $3 $4
        fi
        
        if [ "$5" = "1" ]; then
        crontab_add '* * * * *' /opt/scripts/zfsrep.sh sync $2 $3 $4
        fi

        if [ "$5" = "10" ]; then
        crontab_add '0,10,20,30,40,50 * * * *' /opt/scripts/zfsrep.sh sync $2 $3 $4
        fi
        ;;
'stop')
        crontab_del /opt/scripts/zfsrep.sh
        ;;

'init')
        #---Create the "initial" baseline replication set incase we need to fall back to a safe point
        zfs snapshot -r $2@rep-init-$DATE
        echo "rep-init-$DATE" > $ZFSsnaplog

        if [ "$4" = "" ]; then
           zfs send $2@rep-init-$DATE | zfs receive -F $3
        else
           ssh $port $4 "zfs set readonly=on $3; zfs set replication:locked=true $3"
           zfs send $2@rep-init-$DATE | ssh $port $4 "zfs receive -F $3"
           ssh $port $4 "zfs set readonly=off $3; zfs set replication:locked=false $3"
        fi
        echo "`date`  init-baseline snapshot: $2@rep-init-$DATE > $4:$3@rep$DATE" >> $scriptdir/zfsrep.log

        #---Create first "difference" replication set
        zfs snapshot -r $2@rep$DATE

        #---Make sure the snapshot was taken before attempting to replicate it
        snapchk=`zfs list -t snapshot | grep $2@rep$DATE | awk '{print $1}'`

        if [ "$snapchk" = "$2@rep$DATE" ]; then

           if [ "$4" = "" ]; then
              zfs send -i $2@rep-init-$DATE $2@rep$DATE | zfs receive -F $3
           else
              ssh $port $4 "zfs set readonly=on $3; zfs set replication:locked=true $3"
              zfs send -i $2@rep-init-$DATE $2@rep$DATE | ssh $port $4 "zfs receive -F $3"
              ssh $port $4 "zfs set readonly=off $3; zfs set replication:locked=false $3"
           fi
           echo "`date`  snapshot: $2@rep-init-$DATE > $4:$3@rep$DATE" >> $scriptdir/zfsrep.log

           #---Make sure the snapshot was replicated before removing the old snapshots
           if [ "$4" = "" ]; then
              snapchk=`zfs list -t snapshot | grep $3@rep$DATE | awk '{print $1}'`
           else
              snapchk=`ssh $port $4 "zfs list -t snapshot | grep $3@rep$DATE"`
              snapchk=`echo $snapchk | awk '{print $1}'`
           fi

           #---If snapshot replication was successful, then remove old and init and record log, else remove new snaps
           if [ "$snapchk" = "$3@rep$DATE" ]; then
              echo "rep$DATE" > $ZFSsnaplog
              #zfs destroy $2@rep-init-$DATE 
              #ssh $port $4 "zfs destroy $3@rep-init-$DATE"
           else
              zfs destroy $2@rep$DATE
              err="`date`  Error: Not able to complete the initialization by creating first destination snapshot: $2@rep-init-$DATE > $4:$3@rep$DATE" 
              echo $err >> $scriptdir/zfsrep.log
                if [ "$emailalert" != "" ]; then
                    echo "zfsrep: $err" | mailx -s "zfsrep on `hostname`" $emailalert;    
                fi
           fi

        else
           err="`date`  Error: Not able to complete the initialization by creating first source snapshot: $2@rep-init-$DATE > $4:$3@rep$DATE"
           echo $err >> $scriptdir/zfsrep.log
                if [ "$emailalert" != "" ]; then
                    echo "zfsrep: $err" | mailx -s "zfsrep on `hostname`" $emailalert;    
                fi
        fi
        ;;

'sync')
        zfs snapshot -r $2@rep$DATE

        #check_lu=`ssh $port $4 "stmfadm list-lu -v | awk {'print \$3'} | sed -n -e 1p"`

        #---Make sure the snapshot was taken before attempting to replicate it
        snapchk=`zfs list -t snapshot | grep $2@rep$DATE | awk '{print $1}'`

        if [ "$snapchk" = "$2@rep$DATE" ]; then

           if [ "$4" = "" ]; then
              zfs send -i $2@$OLDsnap $2@rep$DATE | zfs receive -F $3
           else
                #if [ "$check_lu" != "" ]; then
                 #ssh $port $4 "stmfadm delete-lu $check_lu"
                #fi

              ssh $port $4 "zfs set readonly=on $3; zfs set replication:locked=true $3"
              zfs send -i $2@$OLDsnap $2@rep$DATE | ssh $port $4 "zfs receive -F $3" 
              #| mbuffer -s 128k -m 1G -O $4:8000 | ssh $port $4 "mbuffer -s 128k -m 1G -I $int:8000 | zfs receive -F $3"
              ssh $port $4 "zfs set readonly=off $3; zfs set replication:locked=false $3"
           fi

           #---Make sure the snapshot was replicated before removing the old snapshots
           if [ "$4" = "" ]; then
              snapchk=`zfs list -t snapshot | grep $3@rep$DATE`
              snapchk=`echo $snapchk | awk '{print $1}'`
           else
              snapchk=`ssh $port $4 "zfs list -t snapshot | grep $3@rep$DATE"`
              snapchk=`echo $snapchk | awk '{print $1}'`
           fi

           #---If snapshot replication was successful, then remove old snapshot and record log else remove new snaps
           if [ "$snapchk" = "$3@rep$DATE" ]; then

              if [ "$4" = "" ]; then
                 zfs destroy $3@$OLDsnap
              else
                 ssh $port $4 "zfs destroy $3@$OLDsnap"
              fi

              zfs destroy $2@$OLDsnap
              echo "rep$DATE" > $ZFSsnaplog
              echo "`date`  Successfully replicated $2 to $4:$3 at $DATE" >> $scriptdir/zfsrep.log
           else
              zfs destroy $2@rep$DATE
              err="`date`  Error:  Source snapshot ($2@rep$DATE) was sucessful, but failed to replicate it."
              echo $err >> $scriptdir/zfsrep.log
              echo "`date`  May need to manually fall back to baseline snaphot. This will be done automatically in future releases" >> $scriptdir/zfsrep.log
                if [ "$emailalert" != "" ]; then
                    echo "zfsrep: $err" | mailx -s "zfsrep on `hostname`" $emailalert;    
                fi
           fi

        else
           err="`date`  Error:  Source snapshot failed, unable to continue with replication." 
           echo $err >> $scriptdir/zfsrep.log
           echo "`date`  May need to manually fall back to baseline snaphot. This will be done automatically in future releases" >> $scriptdir/zfsrep.log 
            if [ "$emailalert" != "" ]; then
                    echo "zfsrep: $err" | mailx -s "zfsrep on `hostname`" $emailalert;    
            fi
        fi
        ;;

'reverse')
        #Update the LAST zfs snapshot in the log file with the most current one on the old source       
        ssh $port $4 "cat $ZFSsnaplog" > $ZFSsnaplog 
        #ssh $port $4 "stmfadm list-lu -v | awk {'print \$3'} | sed -n -e 1p -e 4p" > $scriptdir/COMSTAR
esac

#---Remove "running" log file for the given replication set
if [ -f $destrun ]; then
   rm $destrun
fi

exit 0
