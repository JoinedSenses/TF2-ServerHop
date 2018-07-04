/*
**
** Server Hop (c) 2009, 2010 [GRAVE] rig0r
**       www.gravedigger-company.nl
**
*/
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <socket>

#define PLUGIN_VERSION "0.9.0"
#define MAX_SERVERS 10
#define REFRESH_TIME 60.0
#define SERVER_TIMEOUT 10.0
#define MAX_STR_LEN 160
#define MAX_INFO_LEN 200
//#define DEBUG

int
	serverCount = 0
	, advertCount = 0
	, advertInterval = 1
	, serverPort[MAX_SERVERS];
char
	serverName[MAX_SERVERS][MAX_STR_LEN]
	, serverAddress[MAX_SERVERS][MAX_STR_LEN]
	, serverInfo[MAX_SERVERS][MAX_INFO_LEN]
	, address[MAXPLAYERS+1][MAX_STR_LEN]
	, server[MAXPLAYERS+1][MAX_INFO_LEN];
bool
	socketError[MAX_SERVERS]
	, connectedFromFavorites[MAXPLAYERS+1];
Handle
	socket[MAX_SERVERS];
ConVar
	cv_hoptrigger
	, cv_serverformat
	, cv_broadcasthops
	, cv_advert
	, cv_advert_interval;

public Plugin myinfo = {
	name = "Server Hop",
	author = "[GRAVE] rig0r, JoinedSenses",
	description = "Provides live server info with join option",
	version = PLUGIN_VERSION,
	url = "https://github.com/JoinedSenses/TF2-ServerHop"
};

public void OnPluginStart() {
	LoadTranslations("serverhop.phrases");

  // convar setup
	cv_hoptrigger = CreateConVar(
		"sm_hop_trigger",
		"!servers",
		"What players have to type in chat to activate the plugin (besides !hop)"
	);
	cv_serverformat = CreateConVar(
		"sm_hop_serverformat",
		"%name - %map (%numplayers/%maxplayers)",
		"Defines how the server info should be presented"
	);
	cv_broadcasthops = CreateConVar(
		"sm_hop_broadcasthops",
		"1",
		"Set to 1 if you want a broadcast message when a player hops to another server"
	);
	cv_advert = CreateConVar(
		"sm_hop_advertise",
		"1",
		"Set to 1 to enable server advertisements"
	);
	cv_advert_interval = CreateConVar(
		"sm_hop_advertisement_interval",
		"1",
		"Advertisement interval: advertise a server every x minute(s)"
	);

	AutoExecConfig(true, "plugin.serverhop");

	Handle timer = CreateTimer(REFRESH_TIME, RefreshServerInfo, _, TIMER_REPEAT);

	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_Say);
	RegConsoleCmd("sm_hop", Command_Hop, "Hop servers.");
	RegConsoleCmd("sm_servers", Command_Servers, "Hop servers.");

	char path[MAX_STR_LEN];

	BuildPath(Path_SM, path, sizeof(path), "configs/serverhop.cfg");
	KeyValues kv = new KeyValues("Servers");

	if (!kv.ImportFromFile(path)) {
		LogToGame("Error loading server list");
	}

	int i;
	kv.Rewind();
	kv.GotoFirstSubKey();
	do {
		kv.GetSectionName(serverName[i], MAX_STR_LEN);
		kv.GetString("address", serverAddress[i], MAX_STR_LEN);
		serverPort[i] = kv.GetNum("port", 27015);
		i++;
	}
	while (kv.GotoNextKey());
	serverCount = i;

	TriggerTimer(timer);
}

public Action Command_Hop(int client, int args) {
	if (!connectedFromFavorites[client]) {
		PrintToChat(client, "\x01[\x03ServerHop\x01] You cannot use this feature, since you didn't connect from \x03favorites\x01. To use this feature, add this server to your favorites and connect through the favorites panel.");
		return Plugin_Handled;
	}
	ServerMenu(client);
	return Plugin_Handled;
}
public Action Command_Servers(int client, int args) {
	ServerMenu(client);
	return Plugin_Handled;
}

public Action Command_Say(int client, int args) {
	char text[MAX_STR_LEN];
	int startidx = 0;

	if (!GetCmdArgString(text, sizeof(text))) {
		return Plugin_Continue;
	}

	if (text[strlen(text) - 1] == '"') {
		text[strlen(text)-1] = '\0';
		startidx = 1;
	}

	char trigger[MAX_STR_LEN];
	cv_hoptrigger.GetString(trigger, sizeof(trigger));

	if (strcmp(text[startidx], trigger, false) == 0 || strcmp(text[startidx], "!hop", false) == 0) {
		ServerMenu(client);
	}

	return Plugin_Continue;
}


public void OnClientAuthorized(int client, const char[] auth) {
	char clientConnectMethod[64];
	GetClientInfo(client, "cl_connectmethod", clientConnectMethod, sizeof(clientConnectMethod));
	if (!StrEqual(clientConnectMethod, "serverbrowser_internet")) {
		connectedFromFavorites[client] = true;
	}
}

public void OnClientDisconnect(int client) {
	connectedFromFavorites[client] = false;
}

public Action ServerMenu(int client) {
	char
		serverNumStr[MAX_STR_LEN]
		, menuTitle[MAX_STR_LEN];
	Menu menu = new Menu(MenuHandler, MENU_ACTIONS_DEFAULT);
	Format(menuTitle, sizeof(menuTitle), "%T", "SelectServer", client);
	menu.SetTitle(menuTitle);

	for (int i = 0; i < serverCount; i++) {
		if (strlen(serverInfo[i]) > 0) {
			#if defined DEBUG then
			PrintToConsole(client, serverInfo[i]);
			#endif
			IntToString(i, serverNumStr, sizeof(serverNumStr));
			menu.AddItem(serverNumStr, serverInfo[i]);
		}
	}
	menu.Display(client, 20);
	return Plugin_Handled;
}

public int MenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char infobuf[MAX_STR_LEN];

		menu.GetItem(param2, infobuf, sizeof(infobuf));
		int serverNum = StringToInt(infobuf);
		char menuTitle[MAX_STR_LEN];
		Format(menuTitle, sizeof(menuTitle), "%T", "AboutToJoinServer", param1);
		Format(address[param1], MAX_STR_LEN, "%s:%i", serverAddress[serverNum], serverPort[serverNum]);
		server[param1] = serverInfo[serverNum];

		Panel panel = new Panel();
		panel.SetTitle(menuTitle);
		panel.DrawText(serverInfo[serverNum]);
		panel.DrawText("Is this correct?");
		panel.CurrentKey = 3;
		panel.DrawItem("Accept");
		panel.DrawItem("Decline");
		panel.Send(param1, MenuConfirmHandler, 15);

		delete panel;
	}
}

public int MenuConfirmHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (param2 == 3) {
		ClientCommand(param1, "redirect %s", address[param1]);
		// broadcast to all
		if (cv_broadcasthops.BoolValue) {
			char clientName[MAX_NAME_LENGTH];
			GetClientName(param1, clientName, sizeof(clientName));
			PrintToChatAll("\x04[\x03hop\x04]\x01 %t", "HopNotification", clientName, server[param1]);
		}
	}
	address[param1] = "";
	server[param1] = "";
}

public Action RefreshServerInfo(Handle timer) {
	for (int i = 0; i < serverCount; i++) {
		serverInfo[i] = "";
		socketError[i] = false;
		socket[i] = SocketCreate(SOCKET_UDP, OnSocketError);
		SocketSetArg(socket[i], i);
		SocketConnect(socket[i], OnSocketConnected, OnSocketReceive, OnSocketDisconnected, serverAddress[i], serverPort[i]);
	}

	CreateTimer(SERVER_TIMEOUT, CleanUp);
}

public Action CleanUp(Handle timer) {
	for (int i = 0; i < serverCount; i++) {
		if (strlen(serverInfo[i]) == 0 && !socketError[i]) {
			LogError("Server %s:%i is down: no timely reply received", serverAddress[i], serverPort[i]);
			delete socket[i];
		}
	}

  // all server info is up to date: advertise
	if (cv_advert.BoolValue) {
		if (advertInterval == cv_advert_interval.FloatValue) {
			Advertise();
		}
		advertInterval++;
		if (advertInterval > cv_advert_interval.FloatValue) {
			advertInterval = 1;
		}
	}
}

public void Advertise() {
	char trigger[MAX_STR_LEN];
	cv_hoptrigger.GetString(trigger, sizeof(trigger));

	// skip servers being marked as down
	while (strlen(serverInfo[advertCount]) == 0) {
		#if defined DEBUG then
		LogError("Not advertising down server %i", advertCount);
		#endif
		advertCount++;
		if (advertCount >= serverCount) {
			advertCount = 0;
			break;
		}
	}

	if (strlen(serverInfo[advertCount]) > 0) {
		PrintToChatAll("\x04[\x03hop\x04]\x01 %t", "Advert", serverInfo[advertCount], trigger);
		#if defined DEBUG then
		LogError("Advertising server %i (%s)", advertCount, serverInfo[advertCount]);
		#endif

		advertCount++;
		if (advertCount >= serverCount) {
			advertCount = 0;
		}
	}
}

public void OnSocketConnected(Handle sock, any i) {
	char requestStr[ 25 ];
	Format(requestStr, sizeof(requestStr), "%s", "\xFF\xFF\xFF\xFF\x54Source Engine Query");
	SocketSend(sock, requestStr, 25);
}

int GetByte(char[] receiveData, int offset) {
	return receiveData[offset];
}

char GetString(char[] receiveData, int dataSize, int offset) {
	char serverStr[MAX_STR_LEN] = "";
	int j = 0;
	for (int i = offset; i < dataSize; i++) {
		serverStr[j] = receiveData[i];
		j++;
		if (receiveData[i] == '\x0') {
			break;
		}
	}
	return serverStr;
}

public void OnSocketReceive(Handle sock, char[] receiveData, const int dataSize, any i) {
	char
		srvName[MAX_STR_LEN]
		, mapName[MAX_STR_LEN]
		, gameDir[MAX_STR_LEN]
		, gameDesc[MAX_STR_LEN]
		, numPlayers[MAX_STR_LEN]
		, maxPlayers[MAX_STR_LEN]
		, format[MAX_STR_LEN];

  // parse server info
	int offset = 2;
	srvName = GetString(receiveData, dataSize, offset);
	offset += strlen(srvName) + 1;
	mapName = GetString(receiveData, dataSize, offset);
	offset += strlen(mapName) + 1;
	gameDir = GetString(receiveData, dataSize, offset);
	offset += strlen(gameDir) + 1;
	gameDesc = GetString(receiveData, dataSize, offset);
	offset += strlen(gameDesc) + 1;
	offset += 2;
	IntToString(GetByte(receiveData, offset), numPlayers, sizeof(numPlayers));
	offset++;
	IntToString(GetByte(receiveData, offset), maxPlayers, sizeof(maxPlayers));

	cv_serverformat.GetString(format, sizeof(format));
	ReplaceString(format, strlen(format), "%name", serverName[i], false);
	ReplaceString(format, strlen(format), "%map", mapName, false);
	ReplaceString(format, strlen(format), "%numplayers", numPlayers, false);
	ReplaceString(format, strlen(format), "%maxplayers", maxPlayers, false);

	serverInfo[i] = format;

	#if defined DEBUG then
	LogError(serverInfo[i]);
	#endif

	delete sock;
}

public void OnSocketDisconnected(Handle sock, any i) {
	delete sock;
}

public void OnSocketError(Handle sock, const int errorType, const int errorNum, any i) {
	LogError("Server %s:%i is down: socket error %d (errno %d)", serverAddress[i], serverPort[i], errorType, errorNum);
	socketError[i] = true;
	delete sock;
}