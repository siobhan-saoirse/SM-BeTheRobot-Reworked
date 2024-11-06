//#pragma semicolon 1
#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
//#include <betherobot>
#include <tf2items>
#include <tf2attributes>
#include <dhooks>

#define PLUGIN_VERSION "1.6.0"

public Plugin:myinfo = 
{
	name        = "Be the Robot (Reworked)",
	author      = "東方Insanity",
	description = "Robots! I will beat you myself!",
	version     = PLUGIN_VERSION
}

/*Shamelessly stolen code from: */
/* 		MasterOfTheXP			*/
/* 		Leonardo				*/
/* 		FlaminSarge				*/
/* 		Pelipoika				*/
/*								*/

enum RobotStatus {
	RobotStatus_Human = 0, // Client is human
	RobotStatus_WantsToBeRobot, // Client wants to be robot, but can't because of defined rules.
	RobotStatus_Robot, // Client is a robot. Beep boop.
	RobotStatus_WantsToBeGiant,
	RobotStatus_Giant
}
new RobotStatus:Status[MAXPLAYERS+1];
new Float:g_flLastTransformTime[MAXPLAYERS+1], Float:flStepThen[MAXPLAYERS+1];
new bool:Locked1[MAXPLAYERS+1], bool:Locked2[MAXPLAYERS+1], bool:Locked3[MAXPLAYERS+1];
new bool:CanWindDown[MAXPLAYERS+1];
new int:AnimEventHook[MAXPLAYERS+1];

Handle g_hHandleAnimEvent;
Handle g_hDispatchAnimEvents;

new Handle:cvarSounds, Handle:cvarTaunts, Handle:cvarCooldown, Handle:cvarBotsAreRobots;

public MRESReturn CBaseAnimating_HandleAnimEvent(int pThis, Handle hParams)
{
	int event = DHookGetParamObjectPtrVar(hParams, 1, 0, ObjectValueType_Int); 
	if (!IsValidClient(pThis) || IsValidClient(pThis) && !IsPlayerAlive(pThis) || !GetConVarBool(cvarSounds))
		return MRES_Ignored;
	if (Status[pThis] == RobotStatus_Robot) {
		if (event == 7001 || event == 59 || event == 58 || event == 66 || event == 65 || event == 6004 || event == 6005 || event == 7005 || event == 7004)
		{
			if (GetEntityFlags(pThis) & FL_ONGROUND)
			{	
				if (TF2_IsPlayerInCondition(pThis,TFCond_Cloaked) || TF2_IsPlayerInCondition(pThis,TFCond_Disguised))
					return MRES_Ignored;
				static char strSound[64];
				switch(GetRandomInt(1,2))
				{
					case 1:	Format(strSound, sizeof(strSound), "mvm/player/footsteps/robostep_0%i.wav", GetRandomInt(1,9));
					case 2: Format(strSound, sizeof(strSound), "mvm/player/footsteps/robostep_%i.wav", GetRandomInt(10,18));

				}
				PrecacheSound(strSound);
				EmitSoundToAll(strSound,pThis,SNDCHAN_STATIC,87,_,0.35,GetRandomInt(95,100));
			}
		}
	}
	return MRES_Ignored;
}

public OnPluginStart()
{
	RegAdminCmd("sm_robot", Command_Robot, ADMFLAG_GENERIC);
	RegAdminCmd("sm_human", Command_Human, ADMFLAG_GENERIC);

	AddCommandListener(Listener_taunt, "taunt");
	AddCommandListener(Listener_taunt, "+taunt");

	AddNormalSoundHook(SoundHook);
	HookEvent("post_inventory_application", Event_Inventory, EventHookMode_Post);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);

	LoadTranslations("common.phrases");
	LoadTranslations("core.phrases");

	CreateConVar("sm_betherobot_reworked_version", PLUGIN_VERSION, "Plugin version.", FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	cvarSounds = CreateConVar("sm_betherobot_reworked_sounds", "1", "If on, robots will emit robotic class sounds instead of their usual sounds.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarTaunts = CreateConVar("sm_betherobot_reworked_taunts", "1", "If on, robots can taunt. Most robot taunts are...incorrect. And some taunt kills don't play an animation for the killing part.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarCooldown = CreateConVar("sm_betherobot_reworked_cooldown", "2.0", "If greater than 0, players must wait this long between enabling/disabling robot on themselves. Set to 0.0 to disable.", FCVAR_NONE, true, 0.0);
	cvarBotsAreRobots = CreateConVar("sm_betherobot_bots_are_robots", "0", "If enabled, all bots turn into robots.", FCVAR_ARCHIVE, true, 0.0);
	
	CreateTimer(0.0, Timer_HalfSecond, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	Handle hConf = LoadGameConfigFile("tf2.betherobot");

	if(hConf == null)
	   SetFailState("Failed to load sdktools gamedata.");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseAnimating::DispatchAnimEvents");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	if ((g_hDispatchAnimEvents = EndPrepSDKCall()) == INVALID_HANDLE) SetFailState("Failed to create SDKCall for CBaseAnimating::DispatchAnimEvents offset!"); 

	//DHooks
	g_hHandleAnimEvent    = DHookCreate(0,  HookType_Entity, ReturnType_Void,   ThisPointer_CBaseEntity, CBaseAnimating_HandleAnimEvent);

	if (!DHookSetFromConf(g_hHandleAnimEvent, hConf, SDKConf_Virtual, "CBaseAnimating::HandleAnimEvent"))
        	SetFailState("Failed to load CBaseAnimating::HandleAnimEvent offset from gamedata");
	DHookAddParam(g_hHandleAnimEvent, HookParamType_ObjectPtr, -1);
	

	Address iAddr = GameConfGetAddress(hConf, "GetAnimationEvent"); 
	if(iAddr == Address_Null) SetFailState("Can't find GetAnimationEvent address for patch.");
	
	StoreToAddress(iAddr, 9999, NumberType_Int16); 

	delete hConf;
	for (new iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsValidEntity(iClient) && !IsClientSourceTV(iClient) && !IsClientReplay(iClient)) {
			OnClientPutInServer(iClient);
		}
	}
}


//I should of have done this long ago.
Handle DHookCreateEx(Handle gc, const char[] key, HookType hooktype, ReturnType returntype, ThisPointerType thistype, DHookCallback callback)
{
	int iOffset = GameConfGetOffset(gc, key);
	if(iOffset == -1)
	{
		SetFailState("Failed to get offset of %s", key);
		return null;
	}
	
	return DHookCreate(iOffset, hooktype, returntype, thistype, callback);
}

/*                                               */
/*-=-=-=-=-=-Below here are the events-=-=-=-=-=-*/
/*                                               */
public OnMapStart()
{
	new String:sModel[PLATFORM_MAX_PATH], String:sClassname[PLATFORM_MAX_PATH];
	for (new TFClassType:iClass = TFClass_Scout; iClass <= TFClass_Engineer; iClass++)
	{
		TF2_GetNameOfClass(iClass, sClassname, sizeof(sClassname));
		Format(sModel, sizeof(sModel), "models/bots/%s_boss/bot_%s_boss.mdl", sClassname, sClassname);
		PrecacheModel(sModel, true);
	}
	
	PrecacheSounds();
}
public OnMapEnd()
{
	for (new iClient = 1; iClient <= MaxClients; iClient++)
	{
		Status[iClient] = RobotStatus_Human;
		g_flLastTransformTime[iClient] = 0.0;
		flStepThen[iClient] = 0.0;
		Locked1[iClient] = false;
		Locked2[iClient] = false;
		Locked3[iClient] = false;
		CanWindDown[iClient] = false;
		FixSounds(iClient);
	}
}

public OnClientPutInServer(iClient)
{
	Status[iClient] = RobotStatus_Human;
	g_flLastTransformTime[iClient] = 0.0;
	flStepThen[iClient] = 0.0;
	Locked1[iClient] = false;
	Locked2[iClient] = false;
	Locked3[iClient] = false;
	CanWindDown[iClient] = false;
	FixSounds(iClient);
	AnimEventHook[iClient] = DHookEntity(g_hHandleAnimEvent, true, iClient, _, CBaseAnimating_HandleAnimEvent);
	SDKHook(iClient, SDKHook_OnTakeDamage, Robot_OnTakeDamage);
	if (GetConVarBool(cvarBotsAreRobots)) {
		if (IsFakeClient(iClient)) {
			Status[iClient] = RobotStatus_Robot;
		}
	}

}
public OnClientDisconnect(iClient)
{
	Status[iClient] = RobotStatus_Human;
	g_flLastTransformTime[iClient] = 0.0;
	flStepThen[iClient] = 0.0;
	Locked1[iClient] = false;
	Locked2[iClient] = false;
	Locked3[iClient] = false;
	CanWindDown[iClient] = false;
	FixSounds(iClient);
	DHookRemoveHookID(AnimEventHook[iClient]);
}

public OnPlayerDeath(Handle:hEvent, const String:strEventName[], bool:bDontBroadcast)
{
	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if(Status[iClient] != RobotStatus_Human)
	{
		FixSounds(iClient);
		AttachParticle(iClient,"bot_death");
	}
}

public Action:Listener_taunt(iClient, const String:command[], args)
{
	if (Status[iClient] == RobotStatus_Robot && !GetConVarBool(cvarTaunts))
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action:Event_Inventory(Handle:hEvent, const String:strEventName[], bool:bDontBroadcast)
{
	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if(Status[iClient] == RobotStatus_Robot)
	{
		new Float:cooldown = GetConVarFloat(cvarCooldown), bool:immediate;
		if (g_flLastTransformTime[iClient] + cooldown <= GetTickedTime()) immediate = true;
		ToggleRobot(iClient, false);
		if (immediate) g_flLastTransformTime[iClient] = 0.0;
		ToggleRobot(iClient, true);
	}
}

public Action:OnTakeDamage(iVictim, &iAttacker, &iInflictor, &Float:flDamage, &iDamagetype, &iWeapon, Float:flDamageForce[3], Float:flDamagePosition[3], iDamagecustom)
{
	return Plugin_Continue;
}

/*                                                   */
/*-=-=-=-=-=-The commands that do commands-=-=-=-=-=-*/
/*                                                   */
public Action:Command_Robot(iClient, nArgs)
{
	if (!iClient && !nArgs)
	{
		new String:arg0[24];
		GetCmdArg(0, arg0, sizeof(arg0));
		ReplyToCommand(iClient, "[SM] Usage: %s <name|#userid> [1/0] - Transforms a player into a robot.", arg0);
		return Plugin_Handled;
	}
	
	new String:arg1[MAX_TARGET_LENGTH], String:arg2[4], bool:toggle = bool:2;
	if (nArgs > 1 && !CheckCommandAccess(iClient, "giant_admin", ADMFLAG_CHEATS))
	{
		//if (!ToggleRobot(iClient)) ReplyToCommand(iClient, "[SM] You can't be a giant right now, but you'll be one as soon as you can.");
		ReplyToCommand(iClient, "[SM] You don't have access to targeting others.");
		return Plugin_Handled;
	}
	else
	{
		GetCmdArg(1, arg1, sizeof(arg1));
		if (nArgs > 1)
		{
			GetCmdArg(2, arg2, sizeof(arg2));
			toggle = bool:StringToInt(arg2);
		}
	}
	if (nArgs < 1)
		arg1 = "@me";	// ¯\_(ツ)_/¯ simpler
	
	new String:target_name[MAX_TARGET_LENGTH], target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	if ((target_count = ProcessTargetString(arg1, iClient, target_list, MAXPLAYERS, (nArgs < 1) ? COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY : COMMAND_FILTER_ALIVE, target_name, sizeof(target_name), tn_is_ml)) <= 0)
	{
		ReplyToTargetError(iClient, target_count);
		return Plugin_Handled;
	}
	for (new i = 0; i < target_count; i++)
	{
		if(!IsValidClass(TF2_GetPlayerClass(target_list[i])))
		{
			ReplyToCommand(iClient, "[SM] They can't be a robot. Accepted classes are: Scout, Pyro, Heavy, Demo, Medic, Soldier, Sniper, Spy, Engineer");
			return Plugin_Handled;
		}
		ToggleRobot(target_list[i], toggle);
	}
	if (toggle != false && toggle != true) ShowActivity2(iClient, "[SM] ", "Toggled being a robot on %s.", target_name);
	else ShowActivity2(iClient, "[SM] ", "%sabled robot on %s.", toggle ? "En" : "Dis", target_name);
	return Plugin_Handled;
}

/*                                                   */
/*-=-=-=-=-=-The commands that do commands-=-=-=-=-=-*/
/*                                                   */
public Action:Command_Human(iClient, nArgs)
{
	if (!iClient && !nArgs)
	{
		new String:arg0[24];
		GetCmdArg(0, arg0, sizeof(arg0));
		ReplyToCommand(iClient, "[SM] Usage: %s <name|#userid> [1/0] - Transforms a player into a giant robot.", arg0);
		return Plugin_Handled;
	}
	
	new String:arg1[MAX_TARGET_LENGTH], String:arg2[4], bool:toggle = bool:2;
	if (nArgs > 1 && !CheckCommandAccess(iClient, "giant_admin", ADMFLAG_CHEATS))
	{
		//if (!ToggleRobot(iClient)) ReplyToCommand(iClient, "[SM] You can't be a giant right now, but you'll be one as soon as you can.");
		ReplyToCommand(iClient, "[SM] You don't have access to targeting others.");
		return Plugin_Handled;
	}
	else
	{
		GetCmdArg(1, arg1, sizeof(arg1));
		if (nArgs > 1)
		{
			GetCmdArg(2, arg2, sizeof(arg2));
			toggle = bool:StringToInt(arg2);
		}
	}
	if (nArgs < 1)
		arg1 = "@me";	// ¯\_(ツ)_/¯ simpler
	
	new String:target_name[MAX_TARGET_LENGTH], target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	if ((target_count = ProcessTargetString(arg1, iClient, target_list, MAXPLAYERS, (nArgs < 1) ? COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY : COMMAND_FILTER_ALIVE, target_name, sizeof(target_name), tn_is_ml)) <= 0)
	{
		ReplyToTargetError(iClient, target_count);
		return Plugin_Handled;
	}
	for (new i = 0; i < target_count; i++)
	{
		if(!IsValidClass(TF2_GetPlayerClass(target_list[i])))
		{
			ReplyToCommand(iClient, "[SM] They can't be a robot. Accepted classes are: Scout, Pyro, Heavy, Demo, Medic, Soldier, Sniper, Spy, Engineer");
			return Plugin_Handled;
		}
		ToggleRobot(target_list[i], false);
	}
	ShowActivity2(iClient, "[SM] ", "Disabled being a robot on %s.", target_name);
	return Plugin_Handled;
}

public Action:Timer_OnPlayerBecomeGiant(Handle:hTimer, any:iClient)
{
	if(Status[iClient] != RobotStatus_Robot || !GetConVarBool(cvarSounds) || !IsValidClient(iClient))
		return Plugin_Stop;
	
	return Plugin_Handled;
}

public Action:SoundHook(iClients[64], &numClients, String:sSound[PLATFORM_MAX_PATH], &iEntity, &iChannel, &Float:flVolume, &iLevel, &iPitch, &fFlags)
{
	if (!GetConVarBool(cvarSounds) || !IsValidEntity(iEntity)) 
		return Plugin_Continue;

	decl String:sClassName[96];
	GetEntityClassname(iEntity, sClassName, sizeof(sClassName));
	if(!strcmp(sClassName, "tf_projectile_pipe") || !strcmp(sClassName, "tf_projectile_rocket"))
	{
		new iClient = GetEntPropEnt(iEntity, Prop_Send, "m_hOriginalLauncher");
		if(!IsValidClient(iClient) || Status[iClient] != RobotStatus_Robot)
			return Plugin_Continue;
		
		if(StrContains(sSound, ")weapons/pipe_bomb", false) != -1 || StrContains(sSound, ")weapons/explode", false) != -1)
			return Plugin_Stop;
	}
	
	if(!strcmp(sClassName, "tf_weapon_grenadelauncher") || !strcmp(sClassName, "tf_weapon_rocketlauncher"))
	{
		new iClient = GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity");
		if(!IsValidClient(iClient) || Status[iClient] != RobotStatus_Robot)
			return Plugin_Continue;
	
		if(StrContains(sSound, ")weapons/grenade_launcher_shoot", false) != -1 || StrContains(sSound, ")weapons/rocket_shoot", false) != -1)
			return Plugin_Stop;
	}
	
	new iClient = iEntity;
	if(!IsValidClient(iClient) || Status[iClient] != RobotStatus_Robot)
		return Plugin_Continue;

	if(StrContains(sSound, "weapons/fx/rics/arrow_impact_flesh", false) != -1)
	{
		Format(sSound, sizeof(sSound), "weapons/fx/rics/arrow_impact_metal%i.wav", GetRandomInt(2,4));
		iPitch = GetRandomInt(90,100);
		EmitSoundToAll(sSound, iClient, SNDCHAN_STATIC, 120, SND_CHANGEVOL, 0.85, iPitch);
		return Plugin_Stop;
	}
	else if(StrContains(sSound, "physics/flesh/flesh_impact_bullet", false) != -1)
	{
		Format(sSound, sizeof(sSound), "physics/metal/metal_solid_impact_bullet%i.wav", GetRandomInt(1,4));
		//EmitSoundToAll(sSound, iClient, SNDCHAN_BODY, 95, SND_CHANGEVOL, 1.0, 100);
		return Plugin_Stop;
	}

	if (StrContains(sSound, "vo/", false) == -1 || StrContains(sSound, "announcer", false) != -1)
		return Plugin_Continue;

	ReplaceString(sSound, sizeof(sSound), "vo/", "vo/mvm/norm/", false);
	ReplaceString(sSound, sizeof(sSound), ".wav", ".mp3", false);
	
	new String:sClassname_MVM[12], String:sClassname[12];
	TF2_GetNameOfClass(TF2_GetPlayerClass(iClient), sClassname, sizeof(sClassname));
	ReplaceString(sClassname, sizeof(sClassname), "demo", "demoman", true);
	Format(sClassname_MVM, sizeof(sClassname_MVM), "%s_mvm", sClassname);
	ReplaceString(sSound, sizeof(sSound), sClassname, sClassname_MVM, false);
	PrecacheSound(sSound);
	return Plugin_Changed;
}

public Action:OnPlayerRunCmd(iClient, &iButtons, &iImpulse, Float:flVelocity[3], Float:flAngle[3], &iWeapon)
{
}

/*                                                             */
/*-=-=-=-=-=-Natives and stocks are below this point-=-=-=-=-=-*/
/*                                                             */

public Action:Robot_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	if (Status[victim] == RobotStatus_Robot) {
		if (damagetype & DMG_BULLET)
		{
			decl String:sSound[PLATFORM_MAX_PATH]
			Format(sSound, sizeof(sSound), "physics/metal/metal_solid_impact_bullet%i.wav", GetRandomInt(1,4));
			EmitSoundToAll(sSound, victim, SNDCHAN_BODY, 95, SND_CHANGEVOL, 1.0, 100);
			new particle = CreateEntityByName("info_particle_system");
			decl String:tName[128];

			if(IsValidEdict(particle))
			{
			// nah....
				//pos[2] += 74;
				TeleportEntity(particle, damagePosition, NULL_VECTOR, NULL_VECTOR);

				Format(tName, sizeof(tName), "target%i", victim);

				DispatchKeyValue(victim, "targetname", tName);
				DispatchKeyValue(particle, "targetname", "tf2particle");
				DispatchKeyValue(particle, "parentname", tName);
				DispatchKeyValue(particle, "effect_name", "bot_impact_heavy");
				DispatchSpawn(particle);

				SetVariantString(tName);
				SetVariantString("flag");
				ActivateEntity(particle);
				AcceptEntityInput(particle, "start");
				CreateTimer(0.25, Timer_Kill, particle); 
			}
			
		}
		return Plugin_Changed;
	}
}

stock bool:ToggleRobot(iClient, bool:toggle = bool:2)
{
	if (Status[iClient] == RobotStatus_WantsToBeRobot && toggle != false && toggle != true) return true;
	if (!Status[iClient] && !toggle) return true;
	if (Status[iClient] == RobotStatus_Robot && toggle == true && CheckTheRules(iClient)) return true;
	if (!IsValidClass(TF2_GetPlayerClass(iClient))) return false;
	
	static Float:fOldStepTime;
	static Float:fOldStepSize;
	if (toggle && (Status[iClient] == RobotStatus_Human) && IsValidClass(TF2_GetPlayerClass(iClient)))
	{
		decl String:sClassname[12];
		TF2_GetNameOfClass(TF2_GetPlayerClass(iClient), sClassname, sizeof(sClassname));
		
		decl String:sModel[PLATFORM_MAX_PATH];
		Format(sModel, sizeof(sModel), "models/bots/%s/bot_%s.mdl", sClassname, sClassname);
		
		SetVariantString(sModel);
		AcceptEntityInput(iClient, "SetCustomModel");
		SetEntProp(iClient, Prop_Send, "m_bUseClassAnimations", 1);
		
		g_flLastTransformTime[iClient] = GetTickedTime();
		Status[iClient] = RobotStatus_Robot;
		
		new weapon = GetPlayerWeaponSlot(iClient, 2);
		TF2Attrib_RemoveByDefIndex(weapon, 128);
		
		CreateTimer(0.05, Timer_OnPlayerBecomeGiant, iClient);
		CreateTimer(0.25, Timer_ModifyItems, iClient); 
		
		SetWearableAlpha(iClient, 0);
		SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
		
		fOldStepTime = GetEntPropFloat(iClient, Prop_Data, "m_flStepSoundTime");
		fOldStepSize = GetEntPropFloat(iClient, Prop_Data, "m_flStepSize");
		if (AnimEventHook[iClient] != -1) {
			DHookRemoveHookID(AnimEventHook[iClient]);
		}
		AnimEventHook[iClient] = DHookEntity(g_hHandleAnimEvent, true, iClient, _, CBaseAnimating_HandleAnimEvent);
	}
	else if (!toggle || (toggle == bool:2 && Status[iClient] == RobotStatus_Robot))
	{
		SetVariantString("");
		AcceptEntityInput(iClient, "SetCustomModel");
		g_flLastTransformTime[iClient] = GetTickedTime();
		Status[iClient] = RobotStatus_Human;
		SetWearableAlpha(iClient, 255);
		FixSounds(iClient);
		RemoveAttributes(iClient);
		SDKUnhook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
		TF2_RegeneratePlayer(iClient);
		DHookRemoveHookID(AnimEventHook[iClient]);
	}
	return true;
}

public OnCvarChanged(Handle:hConvar, const String:oldValue[], const String:newValue[])
{
	if (StringToInt(newValue)) PrecacheSounds();
}

public bool:Filter_Robots(const String:pattern[], Handle:clients)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i)) continue;
		if (Status[i] == RobotStatus_Robot) PushArrayCell(clients, i);
	}
	return true;
}

stock bool:CheckTheRules(iClient)
{
	if (!IsPlayerAlive(iClient)) return false;
	if (TF2_IsPlayerInCondition(iClient, TFCond_Taunting) || TF2_IsPlayerInCondition(iClient, TFCond_Dazed)) return false;
	new Float:cooldowntime = GetConVarFloat(cvarCooldown);
	if (cooldowntime > 0.0 && (g_flLastTransformTime[iClient] + cooldowntime) > GetTickedTime()) return false;
	return true;
}

stock TF2_GetNameOfClass(TFClassType:iClass, String:sName[], iMaxlen)
{
	switch (iClass)
	{
		case TFClass_Scout: Format(sName, iMaxlen, "scout");
		case TFClass_Soldier: Format(sName, iMaxlen, "soldier");
		case TFClass_Pyro: Format(sName, iMaxlen, "pyro");
		case TFClass_DemoMan: Format(sName, iMaxlen, "demo");
		case TFClass_Heavy: Format(sName, iMaxlen, "heavy");
		case TFClass_Engineer: Format(sName, iMaxlen, "engineer");
		case TFClass_Medic: Format(sName, iMaxlen, "medic");
		case TFClass_Sniper: Format(sName, iMaxlen, "sniper");
		case TFClass_Spy: Format(sName, iMaxlen, "spy");
	}
}

stock bool:IsValidClass(TFClassType:iClass)
{
	return (iClass == TFClass_Pyro || iClass == TFClass_Heavy || iClass == TFClass_Sniper || iClass == TFClass_Spy || iClass == TFClass_Engineer || iClass == TFClass_Soldier || iClass == TFClass_DemoMan || iClass == TFClass_Scout || iClass == TFClass_Medic);
}

public Action:Timer_HalfSecond(Handle:hTimer)
{
	for (new iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsValidClient(iClient))
			continue;
			
		if (Status[iClient] == RobotStatus_WantsToBeRobot)
			ToggleRobot(iClient, true);
		else if (Status[iClient] != RobotStatus_Robot)
			FixSounds(iClient);
	}
}

public Action:Timer_ModifyItems(Handle:hTimer, any:iClient)
{
}

public Action:Timer_Kill(Handle:hTimer, any:iEntity)
{
	AcceptEntityInput(iEntity, "Kill")
}

SetAttributes(iClient, iHealth = 3000, Float:flSpeed = 0.5, Float:flForceReduct, Float:flAirblastVuln, Float:flFootstep = 0.0)
{
	new iNewHealth = iHealth-GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
	
	TF2Attrib_SetByName(iClient, "damage force reduction", flForceReduct);
	TF2Attrib_SetByName(iClient, "health from packs decreased", 0.0);
	TF2Attrib_SetByName(iClient, "move speed bonus", flSpeed);
	TF2Attrib_SetByName(iClient, "airblast vulnerability multiplier", flAirblastVuln);
	TF2Attrib_SetByName(iClient, "max health additive bonus", float(iNewHealth));
	
	if(flFootstep > 0.0)
		TF2Attrib_SetByName(iClient, "override footstep sound set", flFootstep);
	
	new iWeapon = GetPlayerWeaponSlot(iClient, 0);
	if(TF2_GetPlayerClass(iClient)==TFClass_Heavy)
		TF2Attrib_SetByName(iWeapon, "aiming movespeed increased", 2.0);
	
	TF2_SetHealth(iClient, iHealth);
	
	TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, 0.1);	// Force-Recalc their speed
}

RemoveAttributes(iClient)
{
	TF2Attrib_RemoveByName(iClient, "damage force reduction");
	TF2Attrib_RemoveByName(iClient, "health from packs decreased");
	TF2Attrib_RemoveByName(iClient, "move speed bonus");
	TF2Attrib_RemoveByName(iClient, "airblast vulnerability multiplier");
	TF2Attrib_RemoveByName(iClient, "overheal fill rate reduced");
	TF2Attrib_RemoveByName(iClient, "max health additive bonus");
	TF2Attrib_RemoveByName(iClient, "override footstep sound set");
	
	new iWeapon = GetPlayerWeaponSlot(iClient, 0);
	if(TF2_GetPlayerClass(iClient)==TFClass_Heavy)
		TF2Attrib_RemoveByName(iWeapon, "aiming movespeed increased");
		
	TF2_RegeneratePlayer(iClient);
}

stock bool:IsValidClient(iClient)
{
	if(iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return false;

	if(IsClientSourceTV(iClient) || IsClientReplay(iClient))
		return false;

	return true;
}

stock bool:IsHumanVoice(String:sSound[])
{
	if(StrContains(sSound, "vo/demoman_", false) != -1
	|| StrContains(sSound, "vo/engineer_", false) != -1
	|| StrContains(sSound, "vo/heavy_", false) != -1
	|| StrContains(sSound, "vo/medic_", false) != -1
	|| StrContains(sSound, "vo/pyro_", false) != -1
	|| StrContains(sSound, "vo/scout_", false) != -1
	|| StrContains(sSound, "vo/sniper_", false) != -1
	|| StrContains(sSound, "vo/soldier_", false) != -1
	|| StrContains(sSound, "vo/spy_", false) != -1
	|| StrContains(sSound, "vo/taunts/", false) != -1)
		return true;

	return false;
}

stock SetWearableAlpha(iClient, iAlpha)
{
	new iCount, iEntity = -1;
	while((iEntity = FindEntityByClassname(iEntity, "tf_wearable*")) != -1)
	{
		new String:sBuffer[64];
		GetEntityClassname(iEntity, sBuffer, sizeof(sBuffer));
		if(StrEqual(sBuffer, "tf_wearable_demoshield")) continue;
		if (iClient != GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity")) continue;
		SetEntityRenderMode(iEntity, RENDER_TRANSCOLOR);
		SetEntityRenderColor(iEntity, 255, 255, 255, iAlpha);
		if (iAlpha == 0) AcceptEntityInput(iEntity, "Kill");
		iCount++;
	}
	return iCount;
}

stock TF2_SetHealth(iClient, iHealth)
{
	if(IsValidClient(iClient))
	{
		SetEntProp(iClient, Prop_Send, "m_iHealth", iHealth);
		SetEntProp(iClient, Prop_Data, "m_iHealth", iHealth);
	}
}

stock UpdatePlayerHitbox(iClient, const Float:flScale)
{
	new Float:vecPlayerMin[3]={-24.5, -25.5, 0.0}, Float:vecPlayerMax[3]={24.5, 24.5, 83.0};
	
	ScaleVector(vecPlayerMin, flScale);
	ScaleVector(vecPlayerMax, flScale);
   
	SetEntPropVector(iClient, Prop_Send, "m_vecSpecifiedSurroundingMins", vecPlayerMin);
	SetEntPropVector(iClient, Prop_Send, "m_vecSpecifiedSurroundingMaxs", vecPlayerMax);
}

FixSounds(iEntity)
{
	if(iEntity <= 0 || !IsValidEntity(iEntity))
		return;
}

stock StopSnd(iEntity, const String:sSound[PLATFORM_MAX_PATH], iChannel = SNDCHAN_AUTO)
{
	if(!IsValidEntity(iEntity))
		return;
	StopSound(iEntity, iChannel, sSound);
}

PrecacheSounds()
{
	PrecacheScriptSound("MVM.BotStep");
}

stock AttachParticle(entity, String:particleType[])
{
    new particle = CreateEntityByName("info_particle_system");
    decl String:tName[128];

    if(IsValidEdict(particle))
    {
        decl Float:pos[3] ;
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	// nah....
        //pos[2] += 74;
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);

        Format(tName, sizeof(tName), "target%i", entity);

        DispatchKeyValue(entity, "targetname", tName);
        DispatchKeyValue(particle, "targetname", "tf2particle");
        DispatchKeyValue(particle, "parentname", tName);
        DispatchKeyValue(particle, "effect_name", particleType);
        DispatchSpawn(particle);

        SetVariantString(tName);
        SetVariantString("flag");
        ActivateEntity(particle);
        AcceptEntityInput(particle, "start");

		CreateTimer(0.25, Timer_Kill, particle); 
        return particle;
    }
    return -1;
}