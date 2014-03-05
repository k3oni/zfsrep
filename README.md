zfsrep
======

Managed ZFS sync Replication/Snapshoting script

  - Provides initial, manual and periodic sync-ing of zfs filesystems
  - Manages snapshots on local and remote filesystem
  - Can snapshot from main to slave and restore from slave to main if available on both systems
  - Stops replication/snapshoting if an error is ancountered(in case it runs automatic using crontab) 

It was build for Illumos/Openindiana, might work on others but there is no guarantee. 

###Requirements

	- 2 ZFS based filesystems on 2 different servers
	- SSH key based login between the two servers

###Script requirements

	scriptdir=""  - location of the script ex. /opt/scripts
	emailalert=""  - you email account, alerts will be sent to this account
	port=""  - ssh port used ex. -p2200


###[Quick How-to](https://github.com/k3oni/zfsrep/wiki)


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/k3oni/zfsrep/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

