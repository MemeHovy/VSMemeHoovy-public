package;

import base.*;
import base.Overlay.Console;
import base.dependency.Discord;
import base.utils.FNFUtils.FNFGame;
import base.utils.FNFUtils.FNFTransition;
import flixel.FlxG;
import flixel.FlxState;
import flixel.addons.transition.FlxTransitionableState;
import haxe.CallStack;
import haxe.Json;
import haxe.io.Path;
import lime.app.Application;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.UncaughtErrorEvent;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

typedef GameWeek =
{
	var songs:Array<WeekSong>;
	var characters:Array<String>;
	@:optional var difficulties:Array<String>; // wip
	var attachedImage:String;
	var storyName:String;
	var startsLocked:Bool;
	var hideOnStory:Bool;
	var hideOnFreeplay:Bool;
	var hideUntilUnlocked:Bool;
}

typedef WeekSong =
{
	var name:String;
	var opponent:String;
	var ?player:String; // wanna do something with this later haha;
	var colors:Array<Int>;
}

// Here we actually import the states and metadata, and just the metadata.
// It's nice to have modularity so that we don't have ALL elements loaded at the same time.
// at least that's how I think it works. I could be stupid!
class Main extends Sprite
{
	public static var game = {
		width: 1280, // game window width
		height: 720, // game window height
		zoom: -1.0, // defines the game's state bounds, -1.0 usually means automatic setup
		initialState: states.TitleState, // state the game should start at
		framerate: 60, // the game's default framerate
		skipSplash: true, // whether to skip the flixel splash screen that appears on release mode
		fullscreen: false, // whether the game starts at fullscreen mode
		versionFE: "0.3.1", // version of Forever Engine Legacy
		versionFF: "0.1", // version of Forever Engine Feather
	};

	public static var baseGame:FNFGame;

	private static var infoCounter:Overlay; // initialize the heads up display that shows information before creating it.
	private static var infoConsole:Console; // intiialize the on-screen console for script debug traces before creating it.

	// weeks set up!
	public static var weeksMap:Map<String, GameWeek> = [];
	public static var weeks:Array<String> = [];

	public static function loadGameWeeks(isStory:Bool)
	{
		weeksMap.clear();
		weeks = [];

		var weekList:Array<String> = CoolUtil.coolTextFile(Paths.txt('data/weekList'));
		for (i in 0...weekList.length)
		{
			if (!weeksMap.exists(weekList[i]))
			{
				if (weekList[i].length > 1)
				{
					var week:GameWeek = parseGameWeeks(Paths.file('data/weeks/' + weekList[i] + '.json'));
					if (week != null)
					{
						if ((isStory && (!week.hideOnStory && !week.hideUntilUnlocked))
							|| (!isStory && (!week.hideOnFreeplay && !week.hideUntilUnlocked)))
						{
							weeksMap.set(weekList[i], week);
							weeks.push(weekList[i]);
						}
					}
				}
				else
					weeks = null;
			}
		}
	}

	inline public static function parseGameWeeks(path:String):GameWeek
	{
		return (FileSystem.exists(path)) ? Json.parse(File.getContent(path)) : null;
	}

	// most of these variables are just from the base game!
	// be sure to mess around with these if you'd like.

	public static function main():Void
		Lib.current.addChild(new Main());

	// calls a function to set the game up
	public function new()
	{
		super();

		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);

		/**
		 * locking neko platforms on 60 because similar to html5 it cannot go over that
		 * avoids note stutters and stuff
		**/
		#if neko
		framerate = 60;
		#end

		// totally didn't steal leathers code, trust me
		FlxG.signals.preStateSwitch.add(() -> {
			FlxG.bitmap.clearCache();

			FlxG.sound.list.forEachAlive((sound:flixel.system.FlxSound) -> {
				FlxG.sound.list.remove(sound, true);
				@:privateAccess
				FlxG.sound.destroySound(sound);
				sound.stop();
				sound.destroy();
			});
			FlxG.sound.list.clear();

			// if above somehow doesn't work
			FlxG.sound.destroy(true);

			var cache:openfl.utils.AssetCache = cast openfl.utils.Assets.cache;
			var lime_cache:lime.utils.AssetCache = cast lime.utils.Assets.cache;

			// this totally isn't copied from polymod/backends/OpenFLBackend.hx trust me
			for (key in cache.bitmapData.keys())
				cache.bitmapData.remove(key);
			for (key in cache.font.keys())
				cache.font.remove(key);
			@:privateAccess
			for (key in cache.sound.keys()) {
				cache.sound.get(key).close();
				cache.sound.remove(key);
			}

			// this totally isn't copied from polymod/backends/LimeBackend.hx trust me
			for (key in lime_cache.image.keys())
				lime_cache.image.remove(key);
			for (key in lime_cache.font.keys())
				lime_cache.font.remove(key);
			for (key in lime_cache.audio.keys()) {
				lime_cache.audio.get(key).dispose();
				lime_cache.audio.remove(key);
			};

			#if cpp
			cpp.vm.Gc.enable(true);
			#end
			openfl.system.System.gc();
		});

		// define the state bounds
		final stageWidth:Int = Lib.current.stage.stageWidth;
		final stageHeight:Int = Lib.current.stage.stageHeight;

		if (game.zoom == -1.0)
		{
			final ratioX:Float = stageWidth / game.width;
			final ratioY:Float = stageHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(stageHeight / game.zoom);
		}

		FlxTransitionableState.skipNextTransIn = true;

		// here we set up the base game
		baseGame = new FNFGame(game.width, game.height, Init, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash,
			game.fullscreen);
		addChild(baseGame); // and create it afterwards

		// initialize the game controls;
		Controls.init();

		// begin the discord rich presence
		#if DISCORD_RPC
		Discord.initializeRPC();
		Discord.changePresence('');
		#end

		infoCounter = new Overlay(0, 0);
		addChild(infoCounter);

		#if SHOW_CONSOLE
		infoConsole = new Console();
		addChild(infoConsole);
		#end

		FlxG.stage.application.window.onClose.add(() -> destroyGame());
	}

	function destroyGame()
	{
		base.Controls.destroy();
		#if DISCORD_RPC
		Discord.shutdownRPC();
		#end
		#if sys
		Sys.exit(1);
		#else
		flash.system.System.exit(1);
		#end
	}

	inline public static function framerateAdjust(input:Float)
	{
		return input * (60 / FlxG.drawFramerate);
	}

	/*  This is used to switch "rooms," to put it basically. Imagine you are in the main menu, and press the freeplay button.
		That would change the game's main class to freeplay, as it is the active class at the moment.
	 */
	public static var lastState:FlxState;

	public static function switchState(curState:FlxState, target:FlxState)
	{
		// Custom made Trans in
		if (!FlxTransitionableState.skipNextTransIn)
		{
			curState.openSubState(new FNFTransition(0.35, false));
			FNFTransition.finishCallback = function()
			{
				FlxG.switchState(target);
			};
			return;
		}
		FlxTransitionableState.skipNextTransIn = false;
		FlxTransitionableState.skipNextTransOut = false;
		// load the state
		FlxG.switchState(target);
	}

	public static function updateFramerate(newFramerate:Int)
	{
		// flixel will literally throw errors at me if I dont separate the orders
		if (newFramerate > FlxG.updateFramerate)
		{
			FlxG.updateFramerate = newFramerate;
			FlxG.drawFramerate = newFramerate;
		}
		else
		{
			FlxG.drawFramerate = newFramerate;
			FlxG.updateFramerate = newFramerate;
		}
	}

	function onCrash(e:UncaughtErrorEvent):Void
	{
		var errMsg:String = "";
		var errMsgPrint:String = "";
		var path:String;
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();

		dateNow = StringTools.replace(dateNow, " ", "_");
		dateNow = StringTools.replace(dateNow, ":", "'");

		path = "crash/" + "Feather_" + dateNow + ".txt";

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
					errMsgPrint += file + ":" + line + "\n"; // if you Ctrl+Mouse Click its go to the line.
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += "\nUncaught Error: " + e.error + " - Please report this error to the\nGitHub page https://github.com/BeastlyGhost/Forever-Engine-Feather";

		if (!FileSystem.exists("crash/"))
			FileSystem.createDirectory("crash/");

		File.saveContent(path, errMsg + "\n");

		Sys.println(errMsgPrint);
		Sys.println("Crash dump saved in " + Path.normalize(path));

		var crashDialoguePath:String = "FEF-CrashDialog";

		#if windows
		crashDialoguePath += ".exe";
		#end

		if (FileSystem.exists(crashDialoguePath))
		{
			Sys.println("Found crash dialog: " + crashDialoguePath);
			new sys.io.Process(crashDialoguePath, [path]);
		}
		else
		{
			Sys.println("No crash dialog found! Making a simple alert instead...");
			Application.current.window.alert(errMsg, "Error!");
		}

		destroyGame();
	}
}
