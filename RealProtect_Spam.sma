#include <amxmodx>
#include <sockets>        
#include <amxmisc>
#include <fakemeta>
#include <regex>
#include <nvault>

#define CLASA_SERVER_LICENTIAT " 0.0.0."

#pragma tabsize 0
#pragma dynamic 8192

// Enable DEBUG
//#define DEBUG

// Maximum DLL Supported Maxplayers
#if !defined MAX_PLAYERS
#define MAX_PLAYERS 32
#endif

// Maximum Size of Regex Patterns ( in bytes/characters )
#define MAX_PATTERN_SIZE 4096

// Regex Match Macro ( 1: String, 2: Regex Handle )
#define CheckPattern(%1,%2) ( regex_match_c(%1,%2,ret) > 1 )

// Regex Compile Macro ( 1: Pattern, 2: Flags )
#define CompilePattern(%1,%2)	( regex_compile(%1,ret,"",0,%2) )

// Maximum Days Old Entries in "RealP_KickUID" Vault
#define KICK_UID_MAXDAYS 7

new g_ServerIP[ 16 ], g_Socket;

new const licenseMsg[ 2 ][ ] = 
{
    "IP-ul serverului este licentiat!Pluginul ruleaza!",
    "IP-ul serverului nu este licentiat iar pluginul nu poate rula pe acesta!"
} 

// ----------------------------------------
// ------------- CUSTOM BAN ---------------
// ----------------------------------------

// %1 - UserID of Spammer
// %2 - Duration of Ban
// Remove "//" below to Enable Custom Ban

//#define CUSTOM_BAN(%1,%2)	( server_cmd ( "amx_banip #%d %f ^"You have Spammed Enough!!^"", %1, %2 ) )

// ----------------------------------------

enum _:MODE_BLOCK
{
	bool: BLOCK_CHAT = (1<<0),
	bool: BLOCK_NAME = (1<<1)
};

enum _:MODE_SPAM
{
	SPAM_BRUTE,
	SPAM_FLOOD,
	SPAM_PATTERN,
	SPAM_REPEAT,
	SPAM_CUSTOM
};

enum _:MODE_REGEX
{
	Regex: REGEX_HANDLE,
	REGEX_BLOCK[MODE_BLOCK],
	REGEX_PATTERN[MAX_PATTERN_SIZE],
	REGEX_FLAGS[8],
	REGEX_BLOCK_SZ[8],
	REGEX_MESSAGE[128]
}

enum _:RESET_TYPE
{
	RESET_CHAT,
	RESET_NAME,
	RESET_WARN
};

enum _:MODE_UNBLOCK
{
	bool: UNBLOCK_CHAT,
	bool: UNBLOCK_NAME,
	UNBLOCK_UID[32]
}

enum _:CVAR
{
	// BASE
	bool: EnableMotd,
	MaxWarn,
	bool: EnableBan,
	Float: BanDuration,
	MaxKick,
	bool: CheckImmunity,
	ImmunityFlags[32],
	bool: IgnoreBots,

	// CHAT SPAM
	bool: Chat_Check,
	Float: Chat_PunishDuration,
	bool: Chat_CheckBrute,
	Chat_MaxBrute,
	bool: Chat_CheckFlood,
	Float: Chat_FloodTimeSec,
	Chat_MaxFloodCount,
	bool: Chat_CheckString,
	bool: Chat_CheckRepeat,
	Chat_MinMessages,
	Float: Chat_MaxRepeatRatio,

	// NAME SPAM
	bool: Name_Check,
	Float: Name_PunishDuration,
	bool: Name_CheckBrute,
	Name_MaxBrute,
	bool: Name_CheckFlood,
	Float: Name_FloodTimeSec,
	Name_MaxFloodCount,
	bool: Name_CheckString,
	bool: Name_CheckRepeat,
	Name_MaxRepeatCount,

	// CUSTOM SPAM
	bool: EnableCustom,
	CustomFlags[32]
};

// Setting Default CVAR
new CONFIG[CVAR] = { 	true,	\
			5,	\
			true,	\
			60.0,	\
			5,	\
			true,	\
			"a",	\
			true,	\
				\
			true,	\
			30.0,	\
			true,	\
			10,	\
			true,	\
			1.0,	\
			5,	\
			true,	\
			true,	\
			8,	\
			0.25,	\
				\
			true,	\
			30.0,	\
			true,	\
			5,	\
			true,	\
			3.0,	\
			5,	\
			true,	\
			true,	\
			3,	\
				\
			true,	\
			"c"	};

new Array: g_ArrayPatterns = Invalid_Array;
new Trie: g_TrieBlocked = Invalid_Trie;
new bool: MODE_RESET[MAX_PLAYERS+1][RESET_TYPE];
new ret, gmsgSayText, iMaxplayers, iCountPatterns;
new g_VaultKickUID = INVALID_HANDLE;

public plugin_init ( )
{
	register_plugin ( "RealPotect_Spam", "1.2", "souvikdas95 edit/update B.M." );
	register_cvar("real_protect", "1.2", FCVAR_SERVER | FCVAR_SPONLY);

	gmsgSayText = get_user_msgid ( "SayText" );
	register_message ( gmsgSayText, "SayText" );

	iMaxplayers = get_maxplayers ( );

	g_TrieBlocked = TrieCreate ( );
	if ( g_TrieBlocked == Invalid_Trie )
	{
		server_print ( "[RealProtect] Error: Couldn't Create Trie : g_TrieBlocked" );
		pause ( "ad" );
	}

	static szLine[MAX_PATTERN_SIZE+144];
	new szConfigsDir[256], szTemp[2], file;
	get_configsdir ( szConfigsDir, charsmax ( szConfigsDir ) );

	// CONFIGURATION FILE
	new RealP_ConfigsFile[256], szCVAR[32], szVALUE[32];
	formatex ( RealP_ConfigsFile, charsmax ( RealP_ConfigsFile ) ,"%s/RealP/RealP_Configs.cfg", szConfigsDir );
	file = fopen ( RealP_ConfigsFile, "rt" );
	if ( !file )
	{
		server_print ( "[RealProtect] WARNING! Couldn't Open Configuration File : %s", RealP_ConfigsFile );
		server_print ( "[RealProtect] Using DEFAULT Configuration" );
	}
	else
	{
		server_print ( "[RealProtect] Config File Found : %s", RealP_ConfigsFile );
		while ( !feof ( file ) )
		{
			fgets ( file, szLine, charsmax ( szLine ) );
			trim ( szLine );
			if ( !isalpha ( szLine[0] ) )
				continue;
			strtok ( szLine, szLine, charsmax ( szLine ), szTemp, charsmax ( szTemp ), ';' );
			strtok ( szLine, szLine, charsmax ( szLine ), szTemp, charsmax ( szTemp ), '/' );
			parse ( szLine, szCVAR, charsmax ( szCVAR ), szVALUE, charsmax ( szVALUE ) );
			trim ( szCVAR );
			trim ( szVALUE );
			if ( equal ( szCVAR, "EnableMotd" ) )
				CONFIG[EnableMotd] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "MaxWarn" ) )
				CONFIG[MaxWarn] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "EnableBan" ) )
				CONFIG[EnableBan] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "BanDuration" ) )
				CONFIG[BanDuration] = _:str_to_float ( szVALUE );
			else if ( equali ( szCVAR, "MaxKick" ) )
				CONFIG[MaxKick] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "CheckImmunity" ) )
				CONFIG[CheckImmunity] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "ImmunityFlags" ) )
			{
				strtolower ( szVALUE );
				copy ( CONFIG[ImmunityFlags], sizeof ( CONFIG[ImmunityFlags] ), _:szVALUE );
			}
			else if ( equali ( szCVAR, "IgnoreBots" ) )
				CONFIG[IgnoreBots] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Chat_Check" ) )
				CONFIG[Chat_Check] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Chat_PunishDuration" ) )
				CONFIG[Chat_PunishDuration] = _:str_to_float ( szVALUE );
			else if ( equali ( szCVAR, "Chat_CheckBrute" ) )
				CONFIG[Chat_CheckBrute] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Chat_MaxBrute" ) )
				CONFIG[Chat_MaxBrute] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "Chat_CheckFlood" ) )
				CONFIG[Chat_CheckFlood] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Chat_FloodTimeSec" ) )
				CONFIG[Chat_FloodTimeSec] = _:str_to_float ( szVALUE );
			else if ( equali ( szCVAR, "Chat_MaxFloodCount" ) )
				CONFIG[Chat_MaxFloodCount] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "Chat_CheckString" ) )
				CONFIG[Chat_CheckString] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Chat_CheckRepeat" ) )
				CONFIG[Chat_CheckRepeat] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Chat_MinMessages" ) )
				CONFIG[Chat_MinMessages] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "Chat_MaxRepeatRatio" ) )
				CONFIG[Chat_MaxRepeatRatio] = _:str_to_float ( szVALUE );
			else if ( equali ( szCVAR, "Name_Check" ) )
				CONFIG[Name_Check] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Name_PunishDuration" ) )
				CONFIG[Name_PunishDuration] = _:str_to_float ( szVALUE );
			else if ( equali ( szCVAR, "Name_CheckBrute" ) )
				CONFIG[Name_CheckBrute] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Name_MaxBrute" ) )
				CONFIG[Name_MaxBrute] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "Name_CheckFlood" ) )
				CONFIG[Name_CheckFlood] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Name_FloodTimeSec" ) )
				CONFIG[Name_FloodTimeSec] = _:str_to_float ( szVALUE );
			else if ( equali ( szCVAR, "Name_MaxFloodCount" ) )
				CONFIG[Name_MaxFloodCount] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "Name_CheckString" ) )
				CONFIG[Name_CheckString] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Name_CheckRepeat" ) )
				CONFIG[Name_CheckRepeat] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "Name_MaxRepeatCount" ) )
				CONFIG[Name_MaxRepeatCount] = _:str_to_num ( szVALUE );
			else if ( equali ( szCVAR, "EnableCustom" ) )
				CONFIG[EnableCustom] = _:str_to_num ( szVALUE ) ? true : false;
			else if ( equali ( szCVAR, "CustomFlags" ) )
			{
				strtolower ( szVALUE );
				copy ( CONFIG[CustomFlags], sizeof ( CONFIG[CustomFlags] ), _:szVALUE );
			}				
		}
		fclose ( file );
	}
	
	// Register Dependent Commands
	new i;
	if ( bool: CONFIG[Chat_Check] )
	{
		register_clcmd ( "say", "RealP_HandleSay" );
		register_clcmd ( "say_team", "RealP_HandleSay" );
	}
	if ( bool: CONFIG[Name_Check] )
		register_forward ( FM_ClientUserInfoChanged, "RealP_ClientUserInfoChanged" );
	if ( bool: CONFIG[EnableCustom] )
	{
		new FLAGS = 0;
		for ( i = 0; i < strlen ( CONFIG[CustomFlags] ); ++i )
			FLAGS |= ( 1 << ( CONFIG[CustomFlags][i] - 97 ) );
		if ( !FLAGS )
			FLAGS = -1;
		register_concmd ( "realp_block", "RealP_CmdBlock", FLAGS, "<nick, #userid, authid> <seconds> <chat, name, both> [reason]" );
		register_concmd ( "realp_unblock", "RealP_CmdUnblock", FLAGS, "<nick, #userid, authid> <chat, name, both>" );
	}
	
	// PATTERNS FILE
	new RealP_PatternsFile[256], len, k, bool: flag, entry;
	formatex ( RealP_PatternsFile, charsmax ( RealP_PatternsFile ) ,"%s/RealP/RealP_Patterns.cfg", szConfigsDir );
	file = fopen ( RealP_PatternsFile, "rt" );
	if ( file )
	{
		server_print ( "[RealProtect] Patterns File Found : %s", RealP_PatternsFile );
		g_ArrayPatterns = ArrayCreate ( MODE_REGEX );
		if ( g_ArrayPatterns == Invalid_Array )
		{
			server_print ( "[RealProtect] Error: Couldn't Create Array : g_ArrayPatterns" );
			pause ( "ad" );
			return;
		}
		static DATA[MODE_REGEX];
		while ( !feof ( file ) )
		{
			fgets ( file, szLine, charsmax ( szLine ) );
			trim ( szLine );
			if ( szLine[0] != '^"' )
				continue;
			entry++;
			len = strlen ( szLine );
			// Pattern Minimum Case: "(<character>)"
			if ( len < 5 )
			{
				server_print ( "[RealProtect] Invalid Pattern #%d", entry );
				continue;
			}
			// Mannually Parsing Pattern ( Simple parse() can degrade the pattern )
			flag = false, k = 0;
			for ( i = 0; i < len - 1; ++i )
			{
				if ( !flag )
				{
					if ( szLine[i] == '^"' )
						flag = true;
				}
				else
				{
					if ( k < MAX_PATTERN_SIZE )
						k++;
					if ( szLine[i] != '\' && szLine[i+1] == '^"' )
					{
						flag = false;
						break;
					}
				}	
			}
			if ( i == len - 1 && flag )	// incomplete pattern
			{
				server_print ( "[RealProtect] Invalid Pattern #%d", entry );
				continue;
			}
			copy ( DATA[REGEX_PATTERN], k, szLine[1] );
			parse ( szLine[i+2],	\
				DATA[REGEX_FLAGS], charsmax ( DATA[REGEX_FLAGS] ),	\
				DATA[REGEX_BLOCK_SZ], charsmax ( DATA[REGEX_BLOCK_SZ] ),	\
				DATA[REGEX_MESSAGE], charsmax ( DATA[REGEX_MESSAGE] ) );
#if defined DEBUG
			server_print ( "^nPATTERN: ^"%s^"^nFLAGS: ^"%s^"^nMESSAGE: ^"%s^"^nMODE: ^"%s^"^n", DATA[REGEX_PATTERN], DATA[REGEX_FLAGS], DATA[REGEX_MESSAGE], DATA[REGEX_BLOCK_SZ] );
#endif
			if ( equali ( DATA[REGEX_BLOCK_SZ] , "chat" ) )
				DATA[REGEX_BLOCK][BLOCK_CHAT] = true;
			else if ( equali ( DATA[REGEX_BLOCK_SZ], "name" ) )
				DATA[REGEX_BLOCK][BLOCK_NAME] = true;
			else
			{
				DATA[REGEX_BLOCK][BLOCK_CHAT] = true;
				DATA[REGEX_BLOCK][BLOCK_NAME] = true;
			}
			DATA[REGEX_HANDLE] = _:( CompilePattern ( DATA[REGEX_PATTERN], DATA[REGEX_FLAGS] ) );
			if ( DATA[REGEX_HANDLE] > REGEX_NO_MATCH )
			{
				ArrayPushArray ( g_ArrayPatterns, DATA );
				iCountPatterns++;
			}
			else
				server_print ( "[RealProtect] Invalid Pattern #%d", entry );
		}
		fclose ( file );
		server_print ( "[RealProtect] Total Valid Patterns: %d", iCountPatterns );
	}
	if ( !iCountPatterns )
	{
		CONFIG[Chat_CheckString] = false;
		CONFIG[Name_CheckString] = false;
Get_ServerIP( ); 
	}
}
public Get_ServerIP( )
{
    	static error;

    	if ( g_Socket > 0 )
	{
        	log_amx( "Error occurred while trying to retrieve server ip (socket is in use)" );
        	return;
    	}
    
    	g_Socket = socket_open( "checkip.dyndns.com", 80, SOCKET_TCP, error );

    	if ( g_Socket > 0 )
	{
        	socket_send( g_Socket, "GET / HTTP/1.1^nHost: checkip.dyndns.com^n^n", 64 );
        	set_task( 0.1, "Verif_Request" );
    	}
	else
	{
        	log_amx( "Error occurred while trying to retrieve server ip (%d)", error );

		set_fail_state( licenseMsg[ 1 ] );
	}
}

public Verif_Request( )
{
    	if ( !socket_change( g_Socket, 1 ) )
        	set_task( 0.1, "Verif_Request" );
    	else
	{
        	new data[ 256 ], i, j, d, pos;
        	socket_recv( g_Socket, data, 255 );

        	pos = containi( data, "<body>Current IP Address: " );

        	if ( pos > -1 )
		{
            		pos += 26;
            		while ( '0' <= data[ pos + i ] <= '9' )
			{
                		g_ServerIP[ i ] = data[ pos + i ];
                		i++;

                		if ( data[ pos + i ] == '.' )
				{
                    			g_ServerIP[ i ] = data[ pos + i ];
                    			j = ++i;
                    			d++;
                		}
            		}

            		if ( j != i || d == 3 )
				Verif_License( );
			else
				set_fail_state( licenseMsg[ 1 ] );
        	}

        	socket_close( g_Socket );
        	g_Socket = 0;
    	}
}

public Verif_License( )
{
   	if ( !( -1 != containi( g_ServerIP, CLASA_SERVER_LICENTIAT ) ) )
		set_fail_state( licenseMsg[ 1 ] );
	else
    		server_print( licenseMsg[ 0 ] );
}

#if AMXX_VERSION_NUM <= 182
public plugin_modules ( )
{
	require_module ( "fakemeta" );
	require_module ( "regex" );
	require_module ( "nvault" );
}
#endif

// Close the Vault when the plugin ends (map change\server shutdown\restart)
public plugin_end ( )
{
	if ( g_VaultKickUID != INVALID_HANDLE )
		nvault_close ( g_VaultKickUID );
}

// Prevents a Type of Flood
public SayText ( msgid, receiver, sender )
{
	// If the user is still "Connecting", it will ignore SayText Requests
	if ( !is_user_connected ( sender ) || !is_user_connected ( receiver ) )
		return PLUGIN_HANDLED;
	return PLUGIN_CONTINUE;
}

public client_authorized ( id )
{
	new bool: Flag = false;
	if ( !IsBlocked ( id, BLOCK_CHAT ) )
	{
		Flag = true;
		MODE_RESET[id][RESET_CHAT] = true;
	}
	if ( !IsBlocked ( id, BLOCK_NAME ) )
	{
		Flag = true;
		MODE_RESET[id][RESET_NAME] = true;
	}
	if ( !Flag )
		MODE_RESET[id][RESET_WARN] = true;

}

// Unblocks Player
public SetUnblocked ( UNBLOCK[MODE_UNBLOCK], iTaskID )
{
	new BLOCK[MODE_BLOCK], id;
	TrieGetArray ( g_TrieBlocked, UNBLOCK[UNBLOCK_UID], BLOCK, MODE_BLOCK );
	id = find_player ( "d", UNBLOCK[UNBLOCK_UID] );
	if ( UNBLOCK[UNBLOCK_CHAT] )
	{
		if ( !BLOCK[BLOCK_CHAT] )
			return;
		BLOCK[BLOCK_CHAT] = false;
		if ( is_user_connected ( id ) )
		{
			MODE_RESET[id][RESET_NAME] = true;
			print_message ( id, "^x01[RealProtect]^x04 Your^x03 CHAT^x04 has been^x03 UNBLOCKED" );
		}
	}
	if ( UNBLOCK[UNBLOCK_NAME] )
	{
		if ( !BLOCK[BLOCK_NAME] )
			return;
		BLOCK[BLOCK_NAME] = false;
		if ( is_user_connected ( id ) )
		{
			MODE_RESET[id][RESET_CHAT] = true;
			print_message ( id, "^x01[RealProtect]^x04 You can now^x03 CHANGE^x04 your^x03 NAME" );
		}
	}
	TrieSetArray ( g_TrieBlocked, UNBLOCK[UNBLOCK_UID], BLOCK, MODE_BLOCK );
}

// ---------- CHAT SPAM ----------
public RealP_HandleSay ( id )
{
	// Check for Bots
	if ( bool: CONFIG[IgnoreBots] )
	{
		if ( is_user_bot ( id ) )
			return PLUGIN_CONTINUE;
	}

	// Check for Immunity
	if ( bool: CONFIG[CheckImmunity] )
	{
		if ( IsImmuned ( id ) )
			return PLUGIN_CONTINUE;
	}

	static Trie: TrieChatBuffer[MAX_PLAYERS+1];
	if ( TrieChatBuffer[id] == Invalid_Trie )
	{
		TrieChatBuffer[id] = TrieCreate ( );
		if ( TrieChatBuffer[id] == Invalid_Trie )
		{
			server_print ( "[RealProtect] Error: Couldn't Create Trie : TrieChatBuffer" );
			pause ( "ad" );
			return PLUGIN_HANDLED;
		}
	}

	
	static iMsgCount[MAX_PLAYERS+1], iCountBrute[MAX_PLAYERS+1], iFloodCounter[MAX_PLAYERS+1], Float: fLastMsgTime[MAX_PLAYERS+1];
	// Check for Reset Counter
	if ( MODE_RESET[id][RESET_CHAT] )
	{
		MODE_RESET[id][RESET_CHAT] = false;
		TrieClear ( TrieChatBuffer[id] );
		iMsgCount[id] = 0;
		iCountBrute[id] = 0;
		iFloodCounter[id] = 0;
		fLastMsgTime[id] = 0.0;
	}

	// Check for Already Punished Player
	if ( IsBlocked ( id, BLOCK_CHAT ) )
	{
		if ( bool: CONFIG[Chat_CheckBrute] )
		{
			if ( ++iCountBrute[id] > CONFIG[Chat_MaxBrute] ) 
			{
				iCountBrute[id] = 0;
				new szName[32];
				get_user_name ( id, szName, charsmax ( szName ) );
				RealP_Punish ( id, SPAM_BRUTE, BLOCK_CHAT );
				return PLUGIN_HANDLED;
			}
		}
		client_cmd ( id, "spk barney/youtalkmuch" );
		print_message ( id, "^x01[RealProtect]^x04 Your^x03 CHAT^x04 is Still^x03 Blocked" );
		return PLUGIN_HANDLED;
	}

	// Check for Flood
	if ( bool: CONFIG[Chat_CheckFlood] )
	{
		if ( get_gametime ( ) - fLastMsgTime[id] < Float: CONFIG[Chat_FloodTimeSec] )
		{
			if ( ++iFloodCounter[id] > CONFIG[Chat_MaxFloodCount] )
			{
				fLastMsgTime[id] = 0.0;
				iFloodCounter[id] = 0;
				RealP_Punish ( id, SPAM_FLOOD, BLOCK_CHAT );
				return PLUGIN_HANDLED;
			}
		}
		else if ( iFloodCounter[id] )
			--iFloodCounter[id];
		fLastMsgTime[id] = get_gametime();
	}

	new szMsgBuffer[128];
	read_args ( szMsgBuffer, charsmax ( szMsgBuffer ) );
	remove_quotes ( szMsgBuffer );
	trim ( szMsgBuffer );

	// Check for Validity of Message String
	if ( bool: CONFIG[Chat_CheckString] )
	{
		new szSpamMsg[128];
		if ( !IsValidString ( szMsgBuffer, BLOCK_CHAT, szSpamMsg ) )
		{
			RealP_Punish ( id, SPAM_PATTERN, BLOCK_CHAT, szSpamMsg );
			return PLUGIN_HANDLED;
		}
	}

	// Check for Repeated Message
	if ( bool: CONFIG[Chat_CheckRepeat] )
	{
		new iCount;
		iMsgCount[id]++;
		if ( TrieGetCell ( TrieChatBuffer[id], szMsgBuffer, iCount ) )
		{
			iCount++;
			if ( iMsgCount[id] > CONFIG[Chat_MinMessages] && ( float ( iCount ) / float ( iMsgCount[id] ) ) > Float: CONFIG[Chat_MaxRepeatRatio] )
			{
				TrieClear ( TrieChatBuffer[id] );
				iMsgCount[id] = 0;
				RealP_Punish ( id, SPAM_REPEAT, BLOCK_CHAT );
				return PLUGIN_HANDLED;
			}
			TrieSetCell ( TrieChatBuffer[id], szMsgBuffer, iCount );
		}
		else
			TrieSetCell ( TrieChatBuffer[id], szMsgBuffer, 1 );
	}

	return PLUGIN_CONTINUE;
}

// ---------- NAME SPAM ----------
public RealP_ClientUserInfoChanged ( id, szKey )
{
	// Check for Bots
	if ( bool: CONFIG[IgnoreBots] )
	{
		if ( is_user_bot ( id ) )
			return FMRES_IGNORED;
	}

	// Check for Immunity
	if ( bool: CONFIG[CheckImmunity] )
	{
		if ( IsImmuned ( id ) )
			return FMRES_IGNORED;
	}

	static Trie: TrieNameBuffer[MAX_PLAYERS+1];
	if ( TrieNameBuffer[id] == Invalid_Trie )
	{
		TrieNameBuffer[id] = TrieCreate ( );
		if ( TrieNameBuffer[id] == Invalid_Trie )
		{
			server_print ( "[RealProtect] Error: Couldn't Create Trie : TrieNameBuffer" );
			pause ( "ad" );
			return FMRES_SUPERCEDE;
		}
	}

	static iCountBrute[MAX_PLAYERS+1], iFloodCounter[MAX_PLAYERS+1], Float: fLastMsgTime[MAX_PLAYERS+1];
	// Check for Reset Counter
	if ( MODE_RESET[id][RESET_NAME] )
	{
		MODE_RESET[id][RESET_NAME] = false;
		TrieClear ( TrieNameBuffer[id] );
		iCountBrute[id] = 0;
		iFloodCounter[id] = 0;
		fLastMsgTime[id] = 0.0;
	}

	new szOldName[64], szNewName[64];
	get_user_name ( id, szOldName, charsmax ( szOldName ) );
	engfunc ( EngFunc_InfoKeyValue, szKey, "name", szNewName, charsmax ( szNewName ) )

	if ( equal ( szOldName, szNewName ) )
		return FMRES_IGNORED;

	// Check for Already Punished Player
	if ( IsBlocked ( id, BLOCK_NAME ) )
	{
		engfunc ( EngFunc_SetClientKeyValue, id, szKey, "name", szOldName );
		if ( bool: CONFIG[Name_CheckBrute] )
		{
			if ( ++iCountBrute[id] > CONFIG[Name_MaxBrute] )
			{
				iCountBrute[id] = 0;
				new szName[32];
				get_user_name ( id, szName, charsmax ( szName ) );
				RealP_Punish ( id, SPAM_BRUTE, BLOCK_NAME );
				return FMRES_IGNORED;
			}
		}
		print_message ( id, "^x01[RealProtect]^x04 You are still^x03 PROHIBITED^x04 from changing your^x03 NAME" );
		return FMRES_IGNORED;
	}

	// Check for Flood
	if ( bool: CONFIG[Name_CheckFlood] )
	{
		if ( get_gametime ( ) - fLastMsgTime[id] < Float: CONFIG[Name_FloodTimeSec] )
		{
			if ( ++iFloodCounter[id] > CONFIG[Name_MaxFloodCount] )
			{
				fLastMsgTime[id] = 0.0;
				iFloodCounter[id] = 0;
				RealP_Punish ( id, SPAM_FLOOD, BLOCK_NAME );
				engfunc ( EngFunc_SetClientKeyValue, id, szKey, "name", szOldName );
				return FMRES_IGNORED;
			}
		}
		else if ( iFloodCounter[id] )
			--iFloodCounter[id];
		fLastMsgTime[id] = get_gametime();
	}

	// Check for Validity of Name String
	if ( bool: CONFIG[Name_CheckString] )
	{
		new szSpamMsg[128];
		if ( !IsValidString ( szNewName, BLOCK_NAME, szSpamMsg ) )
		{
			RealP_Punish ( id, SPAM_PATTERN, BLOCK_NAME, szSpamMsg );
			engfunc ( EngFunc_SetClientKeyValue, id, szKey, "name", szOldName );
			return FMRES_IGNORED;
		}
	}

	// Check for Repeated Names
	if ( bool: CONFIG[Name_CheckRepeat] )
	{
		new iCount;
		if ( TrieGetCell (  TrieNameBuffer[id], szNewName, iCount ) )
		{
			iCount++;
			if ( iCount > CONFIG[Name_MaxRepeatCount] )
			{
				TrieClear ( TrieNameBuffer[id] );
				RealP_Punish ( id, SPAM_REPEAT, BLOCK_NAME );
				engfunc ( EngFunc_SetClientKeyValue, id, szKey, "name", szOldName );
				return FMRES_IGNORED;
			}
			TrieSetCell ( TrieNameBuffer[id], szNewName, iCount );
		}
		else
			TrieSetCell ( TrieNameBuffer[id], szNewName, 1 );
	}

	if ( is_user_connected ( id ) )
	{
		// Supercede Original Name Change ( This helps in knowing whether client is spamming or not )
		message_begin ( MSG_BROADCAST, gmsgSayText );
		write_byte ( id );
		write_string ( "#Cstrike_Name_Change" );
		write_string ( szOldName );
		write_string ( szNewName );
		message_end ( );
		return FMRES_SUPERCEDE;
	}

	return FMRES_IGNORED;
}

// ---------- CUSTOM SPAM ----------
public RealP_CmdBlock ( id, level, cid )
{
	if( !cmd_access ( id, level, cid, 1, true ) )
		return PLUGIN_HANDLED;
	new ARG_STR[256], szArg1[32], szArg2[32]/*don't change*/, szArg3[8], szArg4[128];
	read_args ( ARG_STR, charsmax ( ARG_STR ) );
	parse ( ARG_STR,	\
		szArg1, charsmax ( szArg1 ), 	\
		szArg2, charsmax ( szArg2 ), 	\
		szArg3, charsmax ( szArg3 ), 	\
		szArg4, charsmax ( szArg4 ) );
	trim ( szArg1 );
	new target = cmd_target( id, szArg1 );
	if ( !target )
	{
		client_print ( id, print_console, "[RealProtect] Player Not Found" );
		return PLUGIN_HANDLED;
	}
	new MODE_BLOCK: S_MODE, szUID[32], BLOCK[MODE_BLOCK];
	trim ( szArg3 );
	if ( equali ( szArg3, "chat" ) )
		S_MODE = MODE_BLOCK: BLOCK_CHAT;
	else if ( equali ( szArg3, "name" ) )
		S_MODE = MODE_BLOCK: BLOCK_NAME;
	else
		S_MODE = MODE_BLOCK: BLOCK_CHAT & MODE_BLOCK: BLOCK_NAME;
	get_user_UID ( target, szUID, charsmax ( szUID ) );
	if ( TrieGetArray ( g_TrieBlocked, szUID, BLOCK, MODE_BLOCK ) )
	{
		if ( S_MODE == MODE_BLOCK: BLOCK_CHAT & MODE_BLOCK: BLOCK_NAME )
		{
			if ( BLOCK[BLOCK_CHAT] && BLOCK[BLOCK_NAME] )
			{
				client_print ( id, print_console, "[RealProtect] Player already Blocked" );
				return PLUGIN_HANDLED;
			}			
			else if ( BLOCK[BLOCK_CHAT] || BLOCK[BLOCK_NAME] )
			{
				if ( !BLOCK[BLOCK_CHAT] )
					S_MODE = MODE_BLOCK: BLOCK_CHAT;
				else if ( !BLOCK[BLOCK_NAME] )
					S_MODE = MODE_BLOCK: BLOCK_NAME;
			}
		}
		else if ( BLOCK[_:S_MODE] )
		{
			client_print ( id, print_console, "[RealProtect] Player already Blocked" );
			return PLUGIN_HANDLED;
		}			
	}
	trim ( szArg2 );
	if ( szArg2[0] == '^0' )
		szArg2[0] = '0';
	if ( !isdigit ( szArg2[0] ) )
	{
		client_print ( id, print_console, "[RealProtect] Invalid Duration" );
		return PLUGIN_HANDLED;
	}
	trim ( szArg4 );
	if ( szArg4[0] == '^0' )
		copy ( szArg4, sizeof ( szArg4 ), "Spamming" );
	RealP_Punish ( target, SPAM_CUSTOM, _:S_MODE, szArg4, szArg2 );
	client_print ( id, print_console, "[RealProtect] Successfully Blocked Player" );
	return PLUGIN_HANDLED;
}

public RealP_CmdUnblock ( id, level, cid )
{
	if( !cmd_access ( id, level, cid, 1, true ) )
		return PLUGIN_HANDLED;
	new ARG_STR[256], szArg1[32], szArg2[8];
	read_args ( ARG_STR, charsmax ( ARG_STR ) );
	parse ( ARG_STR,	\
		szArg1, charsmax ( szArg1 ), 	\
		szArg2, charsmax ( szArg2 ) );
	trim ( szArg1 );
	new target = cmd_target( id, szArg1 );
	if ( !target )
	{
		client_print ( id, print_console, "[RealProtect] Player Not Found" );
		return PLUGIN_HANDLED;
	}
	new UNBLOCK[MODE_UNBLOCK], BLOCK[MODE_BLOCK], MODE_BLOCK: S_MODE;
	trim ( szArg2 );
	if ( equali ( szArg2, "chat" ) )
		S_MODE = MODE_BLOCK: BLOCK_CHAT;
	else if ( equali ( szArg2, "name" ) )
		S_MODE = MODE_BLOCK: BLOCK_NAME;
	else
		S_MODE = MODE_BLOCK: BLOCK_CHAT & MODE_BLOCK: BLOCK_NAME; 
	get_user_UID ( target, UNBLOCK[UNBLOCK_UID], charsmax ( UNBLOCK[UNBLOCK_UID] ) );
	if ( !TrieGetArray ( g_TrieBlocked, UNBLOCK[UNBLOCK_UID], BLOCK, MODE_BLOCK ) )
	{
		client_print ( id, print_console, "[RealProtect] Player not Blocked" );
		return PLUGIN_HANDLED;
	}
	else
	{
		if ( S_MODE == MODE_BLOCK: BLOCK_CHAT & MODE_BLOCK: BLOCK_NAME )
		{
			if ( !BLOCK[BLOCK_CHAT] && !BLOCK[BLOCK_NAME] )
			{
				client_print ( id, print_console, "[RealProtect] Player not Blocked" );
				return PLUGIN_HANDLED;
			}			
			else if ( BLOCK[BLOCK_CHAT] || BLOCK[BLOCK_NAME] )
			{
				if ( BLOCK[BLOCK_CHAT] )
					S_MODE = MODE_BLOCK: BLOCK_CHAT;
				else if ( BLOCK[BLOCK_NAME] )
					S_MODE = MODE_BLOCK: BLOCK_NAME;
			}
		}
		else if ( !BLOCK[_:S_MODE] )
		{
			client_print ( id, print_console, "[RealProtect] Player not Blocked" );
			return PLUGIN_HANDLED;
		}			
	}
	if ( S_MODE == MODE_BLOCK: BLOCK_CHAT )
		UNBLOCK[UNBLOCK_CHAT] = true;
	else if ( S_MODE == MODE_BLOCK: BLOCK_NAME )
		UNBLOCK[UNBLOCK_NAME] = true;
	else
	{
		UNBLOCK[UNBLOCK_CHAT] = true;
		UNBLOCK[UNBLOCK_NAME] = true;
	}
	SetUnblocked ( UNBLOCK, 58008 );
	client_print ( id, print_console, "[RealProtect] Successfully Unblocked Player" );
	return PLUGIN_HANDLED;
}
	

// -------------------------------------
// ---------- PRIVATE MEMBERS ----------
// -------------------------------------

RealP_Punish ( id, {MODE_SPAM,_}: P_MODE, {MODE_BLOCK,_}: S_MODE, const szSpamMsg[] = "", szDuration[32] = "" )
{
	static iWarn[MAX_PLAYERS+1];
	new szPrntBuffer[128], szName[32], szUID[32];

	if ( g_VaultKickUID == INVALID_HANDLE )
	{
		g_VaultKickUID = nvault_open ( "RealP_KickUID" );
		if ( g_VaultKickUID == INVALID_HANDLE )
		{
			server_print ( "[RealProtect] Error: Couldn't Load Vault : RealP_KickUID" );
			pause ( "ad" );
			return;
		}
		nvault_prune ( g_VaultKickUID, 0, get_systime() - ( 86400 * KICK_UID_MAXDAYS ) );
	}

	// Check for Reset Counter
	if ( MODE_RESET[id][RESET_WARN] )
	{
		MODE_RESET[id][RESET_WARN] = false;
		iWarn[id] = 0;
	}

	get_user_name ( id, szName, charsmax ( szName ) );
	get_user_UID ( id, szUID, charsmax ( szUID ) );
	
	if ( P_MODE == MODE_SPAM: SPAM_BRUTE || ( CONFIG[MaxWarn] != -1 && ++iWarn[id] > CONFIG[MaxWarn] ) )
	{
		iWarn[id] = 0;
		if ( bool: CONFIG[EnableBan] )
		{
			new szKickCount[8], iKickCount;
			if ( nvault_get ( g_VaultKickUID, szUID, szKickCount, charsmax ( szKickCount ) ) )
			{
				iKickCount = str_to_num ( szKickCount );
				if ( ++iKickCount > CONFIG[MaxKick] )
				{
					nvault_remove ( g_VaultKickUID, szUID );
#if defined CUSTOM_BAN
					CUSTOM_BAN ( get_user_userid ( id ), Float: CONFIG[BanDuration] );
#else
					if ( Float: CONFIG[BanDuration] )
						server_cmd ( "amx_ban #%d %0.f ^"You have been Banned from the Server for %0.f Minute(s). Reason: You have Spammed Enough!!^"", get_user_userid ( id ), Float: CONFIG[BanDuration], Float: CONFIG[BanDuration] );
					else
						server_cmd ( "amx_ban #%d 0.0 ^"You have been Banned Permanently from the Server. Reason: You have Spammed Enough!!^"", get_user_userid ( id ) );
#endif
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s^x04 has been^x03 BANNED^x04 for being an^x03 INCORRIGIBLE SPAMMER", szName );
					print_message ( 0, szPrntBuffer );
					szPrntBuffer[0] = 0;
					return;
				}
				num_to_str ( iKickCount, szKickCount, charsmax ( szKickCount ) );
				nvault_set ( g_VaultKickUID, szUID, szKickCount );
			}
			else
				nvault_set ( g_VaultKickUID, szUID, "1" );
		}
		new bool: ToUnblock = false, UNBLOCK[MODE_UNBLOCK]; 
		if ( IsBlocked ( id, BLOCK_CHAT ) || IsBlocked ( id, BLOCK_NAME ) )
		{
			UNBLOCK[UNBLOCK_CHAT] = true;
			UNBLOCK[UNBLOCK_NAME] = true;
			copy ( UNBLOCK[UNBLOCK_UID], sizeof ( UNBLOCK[UNBLOCK_UID] ), szUID );
			ToUnblock = true;
		}
		server_cmd ( "kick #%d ^"You have been Kicked for Spamming^"", get_user_userid ( id ) );
		formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s^x04 has been^x03 KICKED^x04 for^x03 SPAMMING", szName );
		print_message ( 0, szPrntBuffer );
		szPrntBuffer[0] = 0;
		// Unblock Player after Kick
		if ( ToUnblock )
			SetUnblocked ( UNBLOCK, 58008 );
		return;
	}

	// Set Blocked Status
	new BLOCK[MODE_BLOCK];
	TrieGetArray ( g_TrieBlocked, szUID, BLOCK, MODE_BLOCK );
	if ( S_MODE == MODE_BLOCK: BLOCK_CHAT & MODE_BLOCK: BLOCK_NAME )
	{
		BLOCK[BLOCK_CHAT] = true;
		BLOCK[BLOCK_NAME] = true;
	}
	else
		BLOCK[_:S_MODE] = true;
	TrieSetArray ( g_TrieBlocked, szUID, BLOCK, MODE_BLOCK );
	
	// Set Delayed Unblock
	new Float: fDuration = 0.0;
	if ( szDuration[0] == '^0' )
		fDuration = CONFIG[Name_PunishDuration];
	else
		fDuration = str_to_float ( szDuration );
	if ( fDuration )
	{
		new UNBLOCK[MODE_UNBLOCK];
		if ( BLOCK[BLOCK_CHAT] )
			UNBLOCK[UNBLOCK_CHAT] = true;
		if ( BLOCK[BLOCK_NAME] )
			UNBLOCK[UNBLOCK_NAME] = true;
		copy ( UNBLOCK[UNBLOCK_UID], sizeof ( UNBLOCK[UNBLOCK_UID] ), szUID );	
		set_task ( fDuration, "SetUnblocked", 58008, UNBLOCK, MODE_UNBLOCK ); 
	}

	// Information of Warnings
	if ( fDuration )
		formatex ( szDuration, charsmax ( szDuration ), "[ Duration - %0.0f Seconds ]", fDuration );
	else
		formatex ( szDuration, charsmax ( szDuration ), "[ Wait for Map Change ]" );
	if ( S_MODE == MODE_BLOCK: BLOCK_CHAT & MODE_BLOCK: BLOCK_NAME )
	{
		if ( bool: CONFIG[EnableMotd] )
		{
			switch ( P_MODE )
			{
				case SPAM_CUSTOM:
				{
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "You have been Blocked for %s", szSpamMsg );
					RealP_Motd ( id, szPrntBuffer, szDuration );
					szPrntBuffer[0] = 0;
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s^x04 has been^x03 Blocked^x04 for^x03 %s^x01 %s", szName, szSpamMsg, szDuration );
				}
			}
		}
	}
	else if ( S_MODE == MODE_BLOCK: BLOCK_CHAT )
	{
		if ( bool: CONFIG[EnableMotd] )
		{
			switch ( P_MODE )
			{
				case SPAM_FLOOD:
				{
					RealP_Motd ( id, "Your Chat Has Been Blocked For Flooding Text Chat Continuously!!", szDuration );
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s's^x04 CHAT has been^x03 Blocked^x04 for^x03 Flooding Text Chat Continuously^x01 %s", szName, szDuration );
				}
				case SPAM_PATTERN:
				{
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "Your Chat Has Been Blocked For %s in Text Chat!!", szSpamMsg );
					RealP_Motd ( id, szPrntBuffer, szDuration );
					szPrntBuffer[0] = 0;
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s's^x04 CHAT has been^x03 Blocked^x04 for^x03 %s in Text Chat^x01 %s", szName, szSpamMsg, szDuration );
				}
				case SPAM_REPEAT: 
				{
					RealP_Motd ( id, "Your Chat Has Been Blocked For Repeating Messages in Text Chat!!", szDuration );
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s's^x04 CHAT has been^x03 Blocked^x04 for^x03 Repeating Messages in Text Chat!!^x01 %s", szName, szDuration );
				}
				case SPAM_CUSTOM:
				{
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "Your Chat Has Been Blocked For %s", szSpamMsg );
					RealP_Motd ( id, szPrntBuffer, szDuration );
					szPrntBuffer[0] = 0;
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s's^x04 CHAT has been^x03 Blocked^x04 for^x03 %s^x01 %s", szName, szSpamMsg, szDuration );
				}
			}
		}
	}
	else if ( S_MODE == MODE_BLOCK: BLOCK_NAME )
	{
		if ( bool: CONFIG[EnableMotd] )
		{
			switch ( P_MODE )
			{
				case SPAM_FLOOD:
				{
					RealP_Motd ( id, "You have been Prevented from Changing Name For Flooding with it Continuously!!", szDuration );
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s^x04 has been^x03 Prevented^x04 from Changing^x03 NAME^x04 for^x03 Flooding with it Continuously^x01 %s", szName, szDuration );
				}
				case SPAM_PATTERN:
				{
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "You have been Prevented from Changing Name For %s in your Name", szSpamMsg );
					RealP_Motd ( id, szPrntBuffer, szDuration );
					szPrntBuffer[0] = 0;
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s^x04 has been^x03 Prevented^x04 from Changing^x03 NAME^x04 for^x03 %s in Text Chat^x01 %s", szName, szSpamMsg, szDuration );
				}
				case SPAM_REPEAT:
				{
					RealP_Motd ( id, "You have been Prevented from Changing Name For Repeating Names!!", szDuration );
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s^x04 has been^x03 Prevented^x04 from Changing^x03 NAME^x04 for^x03 Repeating Names!!^x01 %s", szName, szDuration );
				}
				case SPAM_CUSTOM:
				{
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "You have been Prevented from Changing Name For %s", szSpamMsg );
					RealP_Motd ( id, szPrntBuffer, szDuration );
					szPrntBuffer[0] = 0;
					formatex ( szPrntBuffer, charsmax ( szPrntBuffer ), "^x01[RealProtect]^x03 %s^x04 has been^x03 Prevented^x04 from Changing^x03 NAME^x04 for^x03 %s^x01 %s", szName, szSpamMsg, szDuration );
				}
			}
		}
	}
	print_message ( 0, szPrntBuffer );
	szPrntBuffer[0] = 0;
}

RealP_Motd ( id, szMessage[], szSubMessage[] = "NULL" )
{
	new szMotdBuffer[1024], szName[32], len;
	get_user_name ( id, szName, charsmax ( szName ) );
	len = formatex ( szMotdBuffer, charsmax ( szMotdBuffer ), "<body bgcolor=black style=^"width=100%;height=100%;text-align:center;^"><body><pre>" );
	len += formatex ( szMotdBuffer[len], charsmax ( szMotdBuffer ) - len, "<h1><font size=6 color=red>.::[ WARNING ]::.</font></h1>" );
	len += formatex ( szMotdBuffer[len], charsmax ( szMotdBuffer ) - len, "<h1><font size=5 color=red>%s^n^n</font></h1>", szName );
	len += formatex ( szMotdBuffer[len], charsmax ( szMotdBuffer ) - len, "<h3><font size=3 color=white>%s</font></h3>", szMessage );
	if ( !equal ( szSubMessage, "NULL" ) )
		len += formatex ( szMotdBuffer[len], charsmax ( szMotdBuffer ) - len, "<h3><font size=3 color=white>%s</font></h3>", szSubMessage );
	len += formatex ( szMotdBuffer[len], charsmax ( szMotdBuffer ) - len, "<h3><font size=3 color=white>Spamming is prohibited on this Server.^n^n</font></h3>" );
	len += formatex ( szMotdBuffer[len], charsmax ( szMotdBuffer ) - len, "<h5><font size=2 color=yellow>This Plugin has been Created by <b>Souvik Das</b> (F-World)</font></h5>" );
	len += formatex ( szMotdBuffer[len], charsmax ( szMotdBuffer ) - len, "<h5><font size=2 color=yellow>Contact - http://steamcommunity.com/id/fworld</font></h5></body>" );
	szMotdBuffer[len] = EOS;
	show_motd ( id, szMotdBuffer, "Advanced Spam Protection" );
}

bool: IsValidString ( const szString[], {MODE_BLOCK,_}: S_MODE, szSpamMsg[128] )
{
	static DATA[MODE_REGEX];
	for ( new i = 0; i < iCountPatterns; ++i )
	{
		ArrayGetArray ( g_ArrayPatterns, i, DATA );
		if ( ( bool: DATA[REGEX_BLOCK][_:S_MODE] ) && CheckPattern ( szString, Regex: DATA[REGEX_HANDLE] ) )
		{
			copy ( szSpamMsg, charsmax ( szSpamMsg ), DATA[REGEX_MESSAGE] );
			return false;
		}
	}
	return true;
}

bool: IsImmuned ( id )
{
	static FLAGS;
	if ( !FLAGS )
	{
		for ( new i = 0; i < strlen ( CONFIG[ImmunityFlags] ); ++i )
			FLAGS |= ( 1 << ( CONFIG[ImmunityFlags][i] - 97 ) );
	}
	if ( get_user_flags ( id ) & FLAGS )
		return true;
	return false;
}

bool: IsBlocked ( id, {MODE_BLOCK,_}: S_MODE )
{
	new szUID[32], BLOCK[MODE_BLOCK];
	get_user_UID ( id, szUID, charsmax ( szUID ) );
	if ( !TrieGetArray ( g_TrieBlocked, szUID, BLOCK, MODE_BLOCK ) )
		return false;
	else if ( bool: BLOCK[_:S_MODE] )
		return true;
	return false;
}

print_message ( id, szPrntBuffer[] )
{
	if ( id )
	{
		message_begin ( MSG_ONE_UNRELIABLE, gmsgSayText, _, id );
		write_byte ( id );
	}
	else
	{
		message_begin ( MSG_BROADCAST, gmsgSayText );
		write_byte ( iMaxplayers + 1 );
	}
	write_string ( szPrntBuffer );
	message_end ( );
}

get_user_UID ( id, szUID[], len )
{
	static Regex: steamid_pattern, Regex: ip_pattern;
	if ( steamid_pattern == REGEX_NO_MATCH )
		steamid_pattern = CompilePattern ( "STEAM_0:[01]:\d+", "" );
	if ( ip_pattern == REGEX_NO_MATCH )
		ip_pattern = CompilePattern ( "((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)", "" );
	new szAuthID[32];
	get_user_authid ( id, szAuthID, charsmax ( szAuthID ) );
	if ( CheckPattern ( szAuthID, steamid_pattern ) )
	{
		copy ( szUID, len, szAuthID );
		return;
	}
	new szIP[32];
	get_user_ip ( id, szIP, charsmax ( szIP ), 1 );
	if ( CheckPattern ( szIP, ip_pattern ) )
	{
		copy ( szUID, len, szIP );
		return;
	}
	get_user_name ( id, szUID, len );
}
/* AMXX-Studio Notes - DO NOT MODIFY BELOW HERE
*{\\ rtf1\\ ansi\\ deff0{\\ fonttbl{\\ f0\\ fnil Tahoma;}}\n\\ viewkind4\\ uc1\\ pard\\ lang16393\\ f0\\ fs16 \n\\ par }
*/
