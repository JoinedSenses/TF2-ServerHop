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

enum struct ByteReader {
	char data[1024];
	int dataSize;
	int offset;

	void SetData(const char[] data, int dataSize, int offset) {
		for (int i = 0; i < dataSize; ++i) {
			this.data[i] = data[i];
		}
		this.data[dataSize] = 0;
		this.dataSize = dataSize;
		this.offset = offset;
	}

	int GetByte() {
		return this.data[this.offset++];
	}

	int GetShort() {
		int x[2];
		x[0] = this.GetByte();
		x[1] = this.GetByte();
		return x[0] | x[1] << 8;
	}

	int GetLong() {
		int x[2];
		x[0] = this.GetShort();
		x[1] = this.GetShort();
		return x[0] | x[1] << 16;
	}

	void GetLongLong(char[] value, int size) {
		int x[2];
		x[0] = this.GetLong();
		x[1] = this.GetLong();

		KeyValues kv = new KeyValues("");
		kv.SetUInt64("value", x);
		kv.GetString("value", value, size);
		delete kv;
	}

	void GetString(char[] str, int size) {
		int j = 0;
		for (int i = this.offset; i < this.dataSize; ++i, ++j) {
			if (j < size) {
				str[j] = this.data[i];
			}

			if (this.data[i] == '\x0') {
				break;
			}
		}

		this.offset += j + 1;
	}
}

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

	ByteReader byteReader;
	byteReader.SetData(data, dataSize, 4); // begin at 5th byte, index 4

	int header = byteReader.GetByte();

	if (header == 'A') {
		static char reply[A2S_SIZE + 4];

		reply = A2S_INFO;
		for (int i = A2S_SIZE, j = byteReader.offset; i < sizeof(reply); ++i, ++j) {
			PrintToConsole(arg, "%i", (reply[i] = data[j]));
		}
		
		g_Socket.Send(reply, sizeof(reply));

		PrintToConsole(arg, "Sent challenge response: %s%s", reply, reply[25]);

		return;
	}

	int protocol = byteReader.GetByte();

	char srvName[64];
	byteReader.GetString(srvName, sizeof(srvName));

	char mapName[80];
	byteReader.GetString(mapName, sizeof(mapName));

	char gameDir[16];
	byteReader.GetString(gameDir, sizeof(gameDir));

	char gameDesc[64];
	byteReader.GetString(gameDesc, sizeof(gameDesc));

	int gameid = byteReader.GetShort();

	int players = byteReader.GetByte();

	int maxPlayers = byteReader.GetByte();

	int bots = byteReader.GetByte();

	char serverType[16];
	switch (byteReader.GetByte()) {
		case 'd': strcopy(serverType, sizeof(serverType), "Dedicated");
		case 'l': strcopy(serverType, sizeof(serverType), "Non-Dedicated");
		case 'p': strcopy(serverType, sizeof(serverType), "STV Relay");
	}

	char environment[8];
	switch (byteReader.GetByte()) {
		case 'l':      strcopy(environment, sizeof(environment), "Linux");
		case 'w':      strcopy(environment, sizeof(environment), "Windows");
		case 'm', 'o': strcopy(environment, sizeof(environment), "Mac");
	}

	int visibility = byteReader.GetByte();

	int vac = byteReader.GetByte();

	/* TODO:
	 * if gameid == The Ship
	 *   int mode = GetByte;
	 *   int witnesses = GetByte;
	 *   int duration = GetByte;
	 */

	char version[16];
	byteReader.GetString(version, sizeof(version));

	int EDF = byteReader.GetByte();

	int port;
	if (EDF & 0x80) {
		port = byteReader.GetShort();
	}

	char steamid[24];
	if (EDF & 0x10) {
		byteReader.GetLongLong(steamid, sizeof(steamid));
	}

	int stvport;
	char stvserver[64];
	if (EDF & 0x40) {
		stvport = byteReader.GetShort();
		byteReader.GetString(stvserver, sizeof(stvserver));
	}

	char tags[64];
	if (EDF & 0x20) {
		byteReader.GetString(tags, sizeof(tags));
	}

	char gameid64[24];
	if (EDF & 0x01) {
		byteReader.GetLongLong(gameid64, sizeof(gameid64));
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
