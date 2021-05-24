#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <socket> // https://github.com/JoinedSenses/sm-ext-socket/
#include <regex>

#define PLUGIN_NAME "A2SInfo"
#define PLUGIN_AUTHOR "JoinedSenses"
#define PLUGIN_DESCRIPTION "Sends A2S_Info query to a Valve game server"
#define PLUGIN_VERSION "0.1.0"
#define PLUGIN_URL "https://github.com/JoinedSenses"

#define A2S_INFO "\xFF\xFF\xFF\xFF\x54Source Engine Query"
#define A2S_SIZE 25

#define MAX_STR_LEN 160

Regex g_Regex;
Socket g_Socket;

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

public void OnPluginStart() {
	CreateConVar(
		"sm_a2sinfo_version",
		PLUGIN_VERSION,
		PLUGIN_DESCRIPTION,
		FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD
	).SetString(PLUGIN_VERSION);

	RegAdminCmd("sm_a2sinfo", cmdQuery, ADMFLAG_ROOT);

	g_Regex = new Regex("(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})(?:[ \\t]+|:)(\\d{1,5})");
}

public Action cmdQuery(int client, int args) {
	if (!args) {
		ReplyToCommand(client, "Requires arg ip:port");
		return Plugin_Handled;
	}

	char arg[32];
	GetCmdArgString(arg, sizeof(arg));

	RegexError e;
	int ret = g_Regex.Match(arg, e);
	if (ret == -1) {
		ReplyToCommand(client, "Invalid IP:Port. Error: %i", e);
		return Plugin_Handled;
	}

	char ip[24];
	char port[8];

	g_Regex.GetSubString(1, ip, sizeof(ip));
	g_Regex.GetSubString(2, port, sizeof(port));

	ReplyToCommand(client, "Attempting to connect to %s:%i", ip, StringToInt(port));

	delete g_Socket;
	g_Socket = new Socket(SOCKET_UDP, socketError);
	g_Socket.SetArg(client);
	g_Socket.Connect(socketConnect, socketReceive, socketDisconnect, ip, StringToInt(port));

	return Plugin_Handled;
}

public void socketConnect(Socket socket, any arg) {
	PrintToConsole(arg, "Socket connected");
	
	g_Socket.Send(A2S_INFO, A2S_SIZE);
}

public void socketReceive(Socket sock, char[] data, const int dataSize, any arg) {
	PrintToConsole(arg, "Received data: %s %i", data, dataSize);

	/** ==== Request Format
	 * \xFF\xFF\xFF\xFF --------------- | Long
	 * Header: 'T' -------------------- | Byte
	 * Payload: "Source Engine Query\0" | String
	 * Challenge if response header 'A' | Long
	 */

	/** ==== Challenge Response
	 * \xFF\xFF\xFF\xFF --------------- | Long
	 * Header: 'A' -------------------- | Byte
	 * Challenge ---------------------- | Long
	 */

	/** ==== Response
	 * \xFF\xFF\xFF\xFF --------------- | Long
	 * Header: 'I' -------------------- | Byte
	 * Protocol ----------------------- | Byte
	 * Name --------------------------- | String
	 * Map ---------------------------- | String
	 * Folder ------------------------- | String
	 * Game --------------------------- | String
	 * ID ----------------------------- | Short
	 * Players ------------------------ | Byte
	 * Max Players -------------------- | Byte
	 * Bots --------------------------- | Byte
	 * Server type -------------------- | Byte
	 * Environment -------------------- | Byte
	 * Visibility --------------------- | Byte
	 * VAC ---------------------------- | Byte
	 * if The Ship: Mode -------------- | Byte
	 * if The Ship: Witnesses --------- | Byte
	 * if The Ship: Duration ---------- | Byte
	 * Version ------------------------ | String
	 * Extra Data Flag ---------------- | Byte
	 * if EDF & 0x80: Port ------------ | Short
	 * if EDF & 0x10: SteamID --------- | Long Long
	 * if EDF & 0x40: STV Port -------- | Short
	 * if EDF & 0x40: STV Name -------- | String
	 * if EDF & 0x20: Tags ------------ | String
	 * if EDF & 0x01: GameID ---------- | Long Long
	 */

	int offset = 4; // begin at 5th byte, index 4

	int header = GetByte(data, offset);

	if (header == 'A') {
		static char reply[A2S_SIZE + 4];

		reply = A2S_INFO;
		for (int i = A2S_SIZE, j = offset; i < sizeof(reply); ++i, ++j) {
			PrintToConsole(arg, "%i", (reply[i] = data[j]));
		}
		
		g_Socket.Send(reply, sizeof(reply));

		PrintToConsole(arg, "Sent challenge response: %s%s", reply, reply[25]);

		return;
	}

	int protocol = GetByte(data, offset);

	char srvName[MAX_STR_LEN];
	srvName = GetString(data, dataSize, offset);

	char mapName[MAX_STR_LEN];
	mapName = GetString(data, dataSize, offset);

	char gameDir[MAX_STR_LEN];
	gameDir = GetString(data, dataSize, offset);

	char gameDesc[MAX_STR_LEN];
	gameDesc = GetString(data, dataSize, offset);

	int gameid = GetShort(data, offset);

	int players = GetByte(data, offset);

	int maxPlayers = GetByte(data, offset);

	int bots = GetByte(data, offset);

	char serverType[MAX_STR_LEN];
	switch (GetByte(data, offset)) {
		case 'd': serverType = "Dedicated";
		case 'l': serverType = "Non-Dedicated";
		case 'p': serverType = "STV Relay";
	}

	char environment[MAX_STR_LEN];
	switch (GetByte(data, offset)) {
		case 'l': environment = "Linux";
		case 'w': environment = "Windows";
		case 'm', 'o': environment = "Mac";
	}

	int visibility = GetByte(data, offset);

	int vac = GetByte(data, offset);

	/* TODO:
	 * if gameid == The Ship
	 *   int mode = GetByte;
	 *   int witnesses = GetByte;
	 *   int duration = GetByte;
	 */

	char version[MAX_STR_LEN];
	version = GetString(data, dataSize, offset);

	int EDF = GetByte(data, offset);

	int port;
	if (EDF & 0x80) {
		port = GetShort(data, offset);
	}

	char steamid[MAX_STR_LEN];
	if (EDF & 0x10) {
		steamid = GetLongLong(data, offset);
	}

	int stvport;
	char stvserver[MAX_STR_LEN];
	if (EDF & 0x40) {
		stvport = GetShort(data, offset);
		stvserver = GetString(data, dataSize, offset);
	}

	char tags[MAX_STR_LEN];
	if (EDF & 0x20) {
		tags = GetString(data, dataSize, offset);
	}

	char gameid64[MAX_STR_LEN];
	if (EDF & 0x01) {
		gameid64 = GetLongLong(data, offset);
	}
	// end

	PrintToConsole(
		arg,
		"Header: %c\n" ...
		"Protocol: %i\n" ...
		"Server: %s\n" ...
		"Map: %s\n" ...
		"Game Dir: %s\n" ...
		"Game Description: %s\n" ...
		"Game ID: %i\n" ...
		"Number of players: %i\n" ...
		"MaxPlayers: %i\n" ...
		"Humans: %i\n" ...
		"Bots: %i\n" ...
		"Server Type: %s\n" ...
		"Environment: %s\n" ...
		"Visibility: %s\n" ...
		"VAC: %i\n" ...
		"Version: %s\n" ...
		"Port: %i\n" ...
		"Server SteamID: %s\n" ...
		"STV Port: %i\n" ...
		"STV Server: %s\n" ...
		"Tags: %s\n" ...
		"GameID64: %s",
		header,
		protocol,
		srvName,
		mapName,
		gameDir,
		gameDesc,
		gameid,
		players,
		maxPlayers,
		players - bots, // humans
		bots,
		serverType,
		environment,
		visibility ? "Private" : "Public",
		vac,
		version,
		port,
		steamid,
		stvport,
		stvserver,
		tags,
		gameid64
	);

	delete g_Socket;
}

public void socketDisconnect(Socket sock, any arg) {
	delete g_Socket;
	PrintToConsole(arg, "Socket disconnected");
}

public void socketError(Socket socket, const int errorType, const int errorNum, any arg) {
	delete g_Socket;
	PrintToConsole(arg, "Socket error. Type: %i Num %i", errorType, errorNum);
}

int GetByte(const char[] data, int& offset) {
	return data[offset++];
}

int GetShort(const char[] data, int& offset) {
	int x[2];
	x[0] = GetByte(data, offset);
	x[1] = GetByte(data, offset);
	return x[0] | x[1] << 8;
}

int GetLong(const char[] data, int& offset) {
	int x[2];
	x[0] = GetShort(data, offset);
	x[1] = GetShort(data, offset);
	return x[0] | x[1] << 16;
}

char[] GetLongLong(const char[] data, int& offset) {
	char value[MAX_STR_LEN];
	
	int x[2];
	x[0] = GetLong(data, offset);
	x[1] = GetLong(data, offset);

	KeyValues kv = new KeyValues("");
	kv.SetUInt64("value", x);
	kv.GetString("value", value, sizeof(value));
	delete kv;

	return value;
}

char[] GetString(const char[] data, int dataSize, int& offset) {
	char str[MAX_STR_LEN];

	int j = 0;
	for (int i = offset; i < dataSize; ++i, ++j) {
		str[j] = data[i];
		if (data[i] == '\x0') {
			break;
		}
	}

	offset += j + 1;

	return str;
}