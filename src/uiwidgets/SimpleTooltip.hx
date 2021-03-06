/*
 * Scratch Project Editor and Player
 * Copyright (C) 2014 Massachusetts Institute of Technology
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

package uiwidgets;

import openfl.display.DisplayObject;
import openfl.display.*;
import openfl.events.*;
import openfl.filters.DropShadowFilter;
import openfl.geom.*;
import openfl.text.*;
import openfl.utils.Object;
import openfl.utils.Timer;

import translation.Translator;












class SimpleTooltip
{
	// Map of DisplayObject => Strings
	private var tipObjs : Map<DisplayObject,Map<String, String>> = new Map<DisplayObject,Map<String, String>>();
	private var currentTipObj : DisplayObject;
	private var nextTipObj : DisplayObject;

	// Timing values (in milliseconds)
	private static inline var delay : Int = 500;
	private static inline var linger : Int = 1000;
	private static inline var fadeIn : Int = 200;
	private static inline var fadeOut : Int = 500;

	private static inline var bgColor : Int = 0xfcfed4;

	// Timers
	private var showTimer : Timer;
	private var hideTimer : Timer;
	private var animTimer : Timer;

	private var sprite : Sprite;
	private var textField : TextField;
	private var stage : Stage;
	public function new()
	{
		// Setup timers
		showTimer = new Timer(delay);
		showTimer.addEventListener(TimerEvent.TIMER, eventHandler);
		hideTimer = new Timer(linger);
		hideTimer.addEventListener(TimerEvent.TIMER, eventHandler);

		// Setup display objects
		sprite = new Sprite();
		sprite.mouseEnabled = false;
		sprite.mouseChildren = false;
		sprite.filters = [new DropShadowFilter(4, 90, 0, 0.6, 12, 12, 0.8)];
		textField = new TextField();
		textField.autoSize = TextFieldAutoSize.LEFT;
		textField.selectable = false;
		textField.background = false;
		textField.defaultTextFormat = CSS.normalTextFormat;
		textField.textColor = CSS.buttonLabelColor;
		sprite.addChild(textField);
	}

	private static var instance : Dynamic;
	public function addTooltip(dObj : DisplayObject, opts : Map<String, String>) : Void{
		if (!opts.exists("text") || !opts.exists("direction") ||
			["top", "bottom", "left", "right"].indexOf(opts.get('direction')) == -1) {
			trace("Invalid parameters!");
			return;
		}

		if (!tipObjs.exists(dObj)) {
			dObj.addEventListener(MouseEvent.MOUSE_OVER, eventHandler);
		}
		tipObjs[dObj] = opts;
	}

	private function eventHandler(evt : Event) : Void{
		var _sw2_ = (evt.type);        

		switch (_sw2_)
		{
			case MouseEvent.MOUSE_OVER:
				startShowTimer(cast(evt.currentTarget, DisplayObject));
			case MouseEvent.MOUSE_OUT:
				(cast(evt.currentTarget, DisplayObject)).removeEventListener(MouseEvent.MOUSE_OUT, eventHandler);

				if (showTimer.running) {
					showTimer.reset();
					nextTipObj = null;
				}

				startHideTimer(cast(evt.currentTarget, DisplayObject));
			case TimerEvent.TIMER:
				if (evt.target == showTimer) {
					startShow();
				}
				else {
					startHide(cast(evt.target, Timer));
					if (evt.target != hideTimer) {
						(cast(evt.target, Timer)).removeEventListener(TimerEvent.TIMER, eventHandler);
					}
				}
		}
	}

	private function startShow() : Void{
		//trace('startShow()');
		showTimer.reset();
		hideTimer.reset();
		sprite.alpha = 0;
		var ttOpts  = tipObjs[nextTipObj];
		renderTooltip(ttOpts['text']);
		currentTipObj = nextTipObj;

		// TODO: Make it fade in
		sprite.alpha = 1;
		stage.addChild(sprite);

		var pos : Point = getPos(ttOpts['direction']);
		sprite.x = pos.x;
		sprite.y = pos.y;
	}

	public function showOnce(dObj : DisplayObject, ttOpts : Dynamic) : Void{
		if (stage == null && dObj.stage != null)             stage = dObj.stage;  //trace('showOnce()');  ;

		forceHide();
		showTimer.reset();
		hideTimer.reset();
		sprite.alpha = 0;
		renderTooltip(ttOpts.text);
		currentTipObj = dObj;

		// TODO: Make it fade in
		sprite.alpha = 1;
		stage.addChild(sprite);

		var pos : Point = getPos(ttOpts.direction);
		sprite.x = pos.x;
		sprite.y = pos.y;

		// Show the tooltip for twice as long
		var myTimer : Timer = new Timer(5000);
		myTimer.addEventListener(TimerEvent.TIMER, eventHandler);
		myTimer.reset();
		myTimer.start();
	}

	private function getPos(direction : String) : Point{
		var rect : Rectangle = currentTipObj.getBounds(stage);
		var pos : Point = null;
		switch (direction)
		{
			case "right":
				pos = new Point(rect.right + 5, Math.round((rect.top + rect.bottom - sprite.height) / 2));
			case "left":
				pos = new Point(rect.left - 5 - sprite.width, Math.round((rect.top + rect.bottom - sprite.height) / 2));
			case "top":
				pos = new Point(Math.round((rect.left + rect.right - sprite.width) / 2), rect.top - 4 - sprite.height);
			case "bottom":
				pos = new Point(Math.round((rect.left + rect.right - sprite.width) / 2), rect.bottom + 4);
		}
		if (pos.x < 0)             pos.x = 0;
		if (pos.y < 0)             pos.y = 0;
		return pos;
	}

	public function forceHide() : Void{
		startHide(hideTimer);
	}

	private function startHide(timer : Timer) : Void{
		//trace('startHide()');
		hideTimer.reset();
		currentTipObj = null;
		sprite.alpha = 0;
		if (sprite.parent != null)             stage.removeChild(sprite);
	}

	private function renderTooltip(text : String) : Void{
		//trace('renderTooltip(\''+text+'\')');
		var g : Graphics = sprite.graphics;
		textField.text = Translator.map(text);
		g.clear();
		g.lineStyle(1, 0xCCCCCC);
		g.beginFill(bgColor);
		g.drawRect(0, 0, textField.textWidth + 5, textField.textHeight + 3);
		g.endFill();
	}

	private function startShowTimer(dObj : DisplayObject) : Void{
		//trace('startShowTimer()');
		if (stage == null && dObj.stage != null)             stage = dObj.stage;

		dObj.addEventListener(MouseEvent.MOUSE_OUT, eventHandler);

		if (dObj == currentTipObj) {
			hideTimer.reset();
			return;
		}

		if (tipObjs.exists(dObj)) {
			nextTipObj = dObj;

			showTimer.reset();
			showTimer.start();
		}
	}

	private function startHideTimer(dObj : DisplayObject) : Void{
		//trace('startHideTimer()');
		if (dObj != currentTipObj)             return;

		hideTimer.reset();
		hideTimer.start();
	}
}
