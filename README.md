## ServerHop - by [GRAVE] rig0r
This is a fix to ServerHop SourceMod plugin due to valve changing the default value of cl_showpluginmessages  

By default, this plugin has a hardcoded value of 10 MAX_SERVERS. To increase this, you must edit the plugin and recompile.  

### Dependencies
SM 1.10+  
Socket https://github.com/JoinedSenses/sm-ext-socket/  
  
### Installation
```
Install the Socket extension on your server. (http://forums.alliedmods.net/showthread.php?t=67640)  
Download files from repo and add to your sourcemod directory  
Stick your servers into sourcemod/config/serverhop.cfg  
Activate the plugin by refreshing (sm plugins refresh) or restarting your server  
Optionally configure the plugin in cfg/sourcemod/plugin.serverhop.cfg  
```

### Configuration
```
sm_hop_advertise  
  set to 1 to enable server advertisements  
  default: 1  
sm_hop_advertisement_interval  
  advertise a server every x minute(s)  
  default: 1  
sm_hop_trigger  
  specifies what players have to type to activate the plugin (besides !hop)  
  default: "!servers"  
sm_hop_serverformat  
  specifies how server information is presented in the menu  
  default: "%name - %map (%numplayers/%maxplayers)"  
sm_hop_broadcasthops  
  set to 1 to have the plugin display a message to all when a player hops to another server  
  default: 1 
``` 
