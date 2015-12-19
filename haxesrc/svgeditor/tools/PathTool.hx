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

package svgeditor.tools;

import svgeditor.tools.SVGCreateTool;

import flash.display.*;
import flash.events.*;
import flash.events.KeyboardEvent;
import flash.geom.*;
import svgeditor.*;
import svgeditor.objs.SVGShape;
import svgeditor.tools.PathEndPointManager;
import svgutils.*;

@:final class PathTool extends SVGCreateTool
{
    private var newElement : SVGElement;
    private var gfx : Graphics;
    private var svgShape : SVGShape;
    private var shiftDown : Bool;
    private var strokeWidth : Float;
    private var pathContinued : SVGShape;
    private var previewShape : Shape;
    private var indexContinued : Int;
    private var endContinued : Bool;
    private var endMerge : Bool;  // true => new path's end point is touching an existing path to continue it (false => use the start point)  
    private var linesOnly : Bool;
    private var smoothness : Float;
    private static var testWidth : Float = 1;
    
    public function new(svgEditor : ImageEdit, lineTool : Bool = false)
    {
        super(svgEditor, false);
        linesOnly = lineTool;
        cursorBMName = "pencilCursor";
        cursorHotSpot = new Point(0, 16);
        shiftDown = false;
        pathContinued = null;
        indexContinued = -1;
        endContinued = false;
        endMerge = false;
        previewShape = new Shape();
    }
    
    override private function init() : Void{
        super.init();
        if (!linesOnly) {
            STAGE.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress, false, 0, true);
            STAGE.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease, false, 0, true);
        }
        editor.getToolsLayer().mouseEnabled = false;
        mouseEnabled = false;
        mouseChildren = false;
        strokeWidth = editor.getShapeProps().strokeWidth;
        smoothness = editor.getStrokeSmoothness() * 0.01;
        if (Std.is(editor, SVGEdit))             PathEndPointManager.makeEndPoints();
    }
    
    override private function shutdown() : Void{
        STAGE.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
        STAGE.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
        editor.getToolsLayer().mouseEnabled = true;
        PathEndPointManager.removeEndPoints();
        if (previewShape.parent)             previewShape.parent.removeChild(previewShape);
        super.shutdown();
    }
    
    private function onKeyPress(e : KeyboardEvent) : Void{
        shiftDown = e.shiftKey;
    }
    
    private function onKeyRelease(e : KeyboardEvent) : Void{
        shiftDown = e.shiftKey;
        if (currentEvent)             currentEvent.shiftKey = e.shiftKey;
    }
    
    override private function mouseDown(p : Point) : Void{
        // If we're trying to draw with invisible settings then bail
        var props : DrawProperties = editor.getShapeProps();
        if (props.strokeWidth == 0)             props.strokeWidth = 2;
        
        smoothness = editor.getStrokeSmoothness() * 0.01;
        if (props.alpha == 0 || props.strokeWidth < 0.01) 
            return;
        
        PathEndPointManager.toggleEndPoint(false);
        
        beforeLastSavePt = null;
        lastSavePt = null;
        lastSaveC2 = null;
        lastSaveDir = null;
        lastSaveDev = null;
        lastMousePt = null;
        
        newElement = new SVGElement("path", null);
        newElement.setAttribute("d", " ");
        newElement.setShapeStroke(editor.getShapeProps());
        newElement.setAttribute("fill", "none");
        newElement.setAttribute("stroke-linecap", "round");
        newElement.path = new SVGPath();
        
        svgShape = new SVGShape(newElement);
        contentLayer.addChild(svgShape);
        contentLayer.addChild(previewShape);
        newObject = svgShape;
        
        var alpha : Float = Std.parseFloat(newElement.getAttribute("opacity", 1));
        alpha = Math.max(0, Math.min(alpha, 1));
        shiftDown = currentEvent.shiftKey;
        lastSaveTime = (Date.now()).time;
        processMousePos(p);
        
        var retval : Dynamic = getContinuableShape();
        if (retval != null) {
            pathContinued = (try cast(retval.shape, SVGShape) catch(e:Dynamic) null);
            endContinued = retval.bEnd;
            indexContinued = retval.index;
            endMerge = false;
            
            // If continuing a path, use its stroke width instead of the UI setting
            strokeWidth = pathContinued.getElement().getAttribute("stroke-width", 1);
            newElement.setAttribute("stroke-width", strokeWidth);
            newElement.setAttribute("stroke", pathContinued.getElement().getAttribute("stroke"));
            
            // Show only end points that we can connect with?
            PathEndPointManager.makeEndPoints(try cast(pathContinued.parent, Sprite) catch(e:Dynamic) null);
        }
        else {
            strokeWidth = newElement.getAttribute("stroke-width", 1);
        }
        
        gfx = svgShape.graphics;
        setLineStyle(gfx);
        setLineStyle(previewShape.graphics);
        gfx.moveTo(p.x, p.y);
    }
    
    private function setLineStyle(g : Graphics) : Void{
        var stroke : String = newElement.getAttribute("stroke");
        if (stroke != null && (stroke != "none")) {
            g.lineStyle(newElement.getAttribute("stroke-width", 1), newElement.getColorValue(stroke), alpha);
        }
        else {
            g.lineStyle(NaN);
        }
    }
    
    private var lastSaveTime : Int;
    override private function mouseMove(p : Point) : Void{
        if (!editor.isActive())             return;
        shiftDown = currentEvent.shiftKey;
        if (newElement != null) {
            if ((Date.now()).time - lastSaveTime < 100)                 return;
            if (linesOnly && shiftDown) {
                // In line tool, shift forces a vertical or horizontal line.
                p = constrainToVericalOrHorizontal(lastSavePt, p);
            }
            if (linesOnly) {
                previewShape.graphics.clear();
                setLineStyle(previewShape.graphics);
                previewShape.graphics.moveTo(lastSavePt.x, lastSavePt.y);
                previewShape.graphics.lineTo(p.x, p.y);
            }
            else {
                lastSaveTime = (Date.now()).time;
                processMousePos(p);
            }
        }
        
        var retval : Dynamic = getContinuableShape();
        if (retval != null) {
            var s : SVGShape = retval.shape;
            var path : SVGPath = s.getElement().path;
            p = editor.getToolsLayer().globalToLocal(s.localToGlobal(path.getPos(retval.index)));
            PathEndPointManager.updateOrb(true, p);
        }
    }
    
    private function constrainToVericalOrHorizontal(lastP : Point, p : Point) : Point{
        // Return a new point that makes a vertical or horizontal line from lastP.
        var dx : Int = Math.abs(p.x - lastSavePt.x);
        var dy : Int = Math.abs(p.y - lastSavePt.y);
        return ((dx > dy)) ? 
        new Point(p.x, lastSavePt.y) : 
        new Point(lastSavePt.x, p.y);
    }
    
    // Remove points that reside on a line between two other points on the path
    // Remove points that are too close to their neighbors
    private static inline var dotProd : Float = 0.985;
    private var beforeLastSavePt : Point;
    private var lastSavePt : Point;
    private var lastSaveC2 : Point;
    private var lastSaveDir : Point;
    private var lastSaveDev : Point;
    private var lastMousePt : Point;
    private function processMousePos(mousePos : Point, final : Bool = false) : Void{
        var maxDev : Float = Math.min(smoothness, strokeWidth * 0.4);
        var maxDevDiff : Float = Math.min(smoothness, strokeWidth);
        var maxDot : Float = (smoothness < (1) ? Math.pow(dotProd, smoothness) : dotProd);
        //			var maxDist:Number = Math.max(1, strokeWidth * 10);
        if (lastSavePt != null && mousePos.subtract(lastSavePt).length < strokeWidth && !final) 
            return;
        
        if (lastSaveDir == null) {
            if (lastMousePt == null) {
                lastSaveC2 = mousePos;
                lastMousePt = mousePos;
                lastSavePt = mousePos;
                newElement.path.push(["M", mousePos.x, mousePos.y]);
                
                previewShape.graphics.clear();
                previewShape.graphics.moveTo(mousePos.x, mousePos.y);
                setLineStyle(previewShape.graphics);
                return;
            }
            
            lastSaveDir = mousePos.subtract(lastMousePt);
            lastMousePt = mousePos;
            previewShape.graphics.lineTo(mousePos.x, mousePos.y);
            //lastSaveDir.normalize(1);
            return;
        }
        
        var curDir : Point = mousePos.subtract(lastMousePt);
        lastMousePt = mousePos;
        //			var div:Number = curDir.length*lastSaveDir.length;
        //			if (div == 0) div = 0.01;
        //			var factor:Number = (curDir.x * lastSaveDir.x + curDir.y * lastSaveDir.y) / div;
        //trace('dot product = '+factor);
        var distFromLastSaved : Float = mousePos.subtract(lastSavePt).length;
        var np : Point = lastSaveDir.clone();
        np.normalize(distFromLastSaved);
        var proj : Point = np.add(lastSavePt);
        var dev : Point = mousePos.subtract(proj);
        if (lastSaveDev != null) {
            /*
previewShape.graphics.clear();
previewShape.graphics.lineStyle(3, 0xFF0000);
previewShape.graphics.drawCircle(lastSavePt.x, lastSavePt.y, 8);
previewShape.graphics.moveTo(lastSavePt.x, lastSavePt.y);
previewShape.graphics.lineTo(proj.x, proj.y);
*/
            var div : Float = dev.length * lastSaveDev.length;
            if (div == 0)                 div = 0.01;
            var factor : Float = (dev.x * lastSaveDev.x + dev.y * lastSaveDev.y) / div;
        }  //trace('np=('+np.x+', '+np.y+')');    //trace('distFromLastSaved='+distFromLastSaved+'   '+dev+' > '+maxDev);    //			if(factor < dotProd && distFromLastSaved > maxDist || dev > maxDev || final) {  
        
        
        
        
        
        var devDiff : Float = (lastSaveDev != null) ? Math.abs(dev.length - lastSaveDev.length) : 0;
        //trace('('+dev.length+' > '+maxDev+' && (!'+(!!lastSaveDev)+' || '+factor+' < '+dotProd+' || '+devDiff+' > '+strokeWidth+')');
        //if((dev.length > maxDev && (!lastSaveDev || factor < dotProd || devDiff > strokeWidth)) || final) {
        if (((dev.length > maxDev && lastSaveDev == null) || factor < maxDot || devDiff > maxDevDiff) || final) {
            var before : Point = beforeLastSavePt || lastSavePt;
            var here : Point = lastSavePt;
            var after : Point = mousePos;
            var cPts : Array<Dynamic> = SVGPath.getControlPointsAdjacentAnchor(before, here, after);
            var c1 : Point = cPts[0];
            var c2 : Point = cPts[1];
            
            SVGPath.drawCubicBezier(gfx, before, lastSaveC2, c1, here, null, null);
            newElement.path.push(["C", lastSaveC2.x, lastSaveC2.y, c1.x, c1.y, here.x, here.y]);
            lastSaveC2 = c2;
            previewShape.graphics.clear();
            previewShape.graphics.moveTo(here.x, here.y);
            
            beforeLastSavePt = lastSavePt;
            lastSavePt = mousePos;
            lastSaveDir = curDir;
            lastSaveDev = dev;
            //lastSaveDir.normalize(1);
            
            setLineStyle(previewShape.graphics);
            SVGPath.drawCubicBezier(previewShape.graphics, here, c2, after, after, null, null);
            
            if (final) {
                // Append the final path command
                SVGPath.drawCubicBezier(gfx, before, c2, after, after, null, null);
                newElement.path.push(["C", c2.x, c2.y, after.x, after.y, after.x, after.y]);
            }
        }
        else {
            //trace(factor+' < '+dotProd+' && '+distFromLastSaved+' > '+maxDist+' || '+dev+' > '+maxDev);
            previewShape.graphics.lineTo(mousePos.x, mousePos.y);
        }
    }
    
    override public function refresh() : Void{
        // Refresh the end points
        PathEndPointManager.makeEndPoints();
    }
    
    private function getContinuableShape() : Dynamic{
        // Hide the current path so we don't get that
        if (svgShape != null) 
            svgShape.visible = false;
        var retval : Dynamic = getContinuableShapeUnderMouse(strokeWidth);
        if (svgShape != null) 
            svgShape.visible = true;
        
        return retval;
    }
    
    override private function mouseUp(newP : Point) : Void{
        shiftDown = currentEvent.shiftKey;
        previewShape.graphics.clear();
        if (newElement == null)             return;
        
        if (linesOnly && shiftDown) {
            // In line tool, shift forces a vertical or horizontal line.
            newP = constrainToVericalOrHorizontal(lastSavePt, newP);
        }
        
        if (linesOnly) 
            newElement.path.push(["L", newP.x, newP.y])
        else 
        processMousePos(newP, true);
        
        previewShape.graphics.clear();
        
        // Now convert the points to a path
        var p : Point;
        if (newElement.path.length > 1) {
            // If we're editing a backdrop and an endpoint is near the edge, place it on the edge
            if (editor.editingScene()) {
                p = newElement.path.getPos(0);
                if (p.x < 5)                     p.x = -5;
                if (p.x > ImageCanvas.canvasWidth - 5)                     p.x = ImageCanvas.canvasWidth + 5;
                if (p.y < 5)                     p.y = -5;
                if (p.y > ImageCanvas.canvasHeight - 5)                     p.y = ImageCanvas.canvasHeight + 5;
                newElement.path[0][1] = p.x;
                newElement.path[0][2] = p.y;
                
                var lastIdx : Int = newElement.path.length - 1;
                p = newElement.path.getPos(lastIdx);
                if (p.x < 5)                     p.x = -5;
                if (p.x > ImageCanvas.canvasWidth - 5)                     p.x = ImageCanvas.canvasWidth + 5;
                if (p.y < 5)                     p.y = -5;
                if (p.y > ImageCanvas.canvasHeight - 5)                     p.y = ImageCanvas.canvasHeight + 5;
                if (newElement.path[lastIdx][0] == "L") {
                    newElement.path[lastIdx][1] = p.x;
                    newElement.path[lastIdx][2] = p.y;
                }
                else if (newElement.path[lastIdx][0] == "C") {
                    newElement.path[lastIdx][3] = p.x;
                    newElement.path[lastIdx][4] = p.y;
                    newElement.path[lastIdx][5] = p.x;
                    newElement.path[lastIdx][6] = p.y;
                }
            }
            
            processPath();
        }
        // Set drawnPts to null to indicate we aren't drawing
        else if (newElement.path.length) {
            // Draw a dot
            newElement.tag = "path";
            var ofs : Float = 0.3;
            p = newElement.path.getPos(0);
            newElement.setAttribute("d", "M " + p.x + " " + p.y + " " + "L " + (ofs + p.x) + " " + (ofs + p.y));
            newElement.setAttribute("stroke-linecap", "round");
            newElement.updatePath();
            svgShape.redraw();
        }
        
        
        
        gfx = null;
        newElement = null;
        svgShape = null;
        pathContinued = null;
        
        // Refresh the end points
        PathEndPointManager.makeEndPoints();
        
        dispatchEvent(new Event(Event.CHANGE));
    }
    
    private function processPath() : Void{
        var firstPt : Point = newElement.path.getPos(0);
        
        if (newElement.path.getPos(1).subtract(firstPt).length < 1) {
            newElement.path.splice(1, 1);
            newElement.path.adjustPathAroundAnchor(1);
            
            // If the user simply clicked and didn't make a line with the line tool
            // then discard the shape
            if (linesOnly) {
                svgShape.parent.removeChild(svgShape);
                return;
            }
        }
        
        if (strokeWidth > 1.5 && newElement.path.length < 100) {
            //trace('Smoothing path of '+newElement.path.length+' commands.');
            svgShape.smoothPath2(editor.getStrokeSmoothness());
        }  // Continue the path that the user started drawing from the end of...  
        
        
        
        var tryIntersection : Bool = !pathContinued;
        var pathClosed : Bool = false;
        if (pathContinued != null) {
            if (svgShape.connectPaths(pathContinued)) {
                pathContinued.parent.removeChild(pathContinued);
            }
        }  // Close the path?  
        
        
        
        var endPts : Array<Dynamic> = newElement.path.getSegmentEndPoints();
        if (!newElement.path.getSegmentEndPoints()[2] &&
            newElement.path.getPos(0).subtract(newElement.path.getPos(newElement.path.length - 1)).length < strokeWidth * 2) {
            newElement.path.push(["Z"]);
            newElement.path.adjustPathAroundAnchor(newElement.path.length - 2);
            newElement.path.adjustPathAroundAnchor(1);
            
            if (strokeWidth > 1.5 && newElement.path.length < 100) {
                //trace('Smoothing path of '+newElement.path.length+' commands.');
                svgShape.smoothPath2(editor.getStrokeSmoothness());
            }
            
            newElement.path.adjustPathAroundAnchor(newElement.path.length - 2);
            newElement.path.adjustPathAroundAnchor(1);
            tryIntersection = false;
        }
        else {
            var retval : Dynamic = getContinuableShape();
            if (retval != null) {
                pathContinued = (try cast(retval.shape, SVGShape) catch(e:Dynamic) null);
                if (svgShape.connectPaths(pathContinued)) {
                    pathContinued.parent.removeChild(pathContinued);
                    
                    // Close the path?
                    endPts = newElement.path.getSegmentEndPoints();
                    if (!newElement.path.getSegmentEndPoints()[2] &&
                        newElement.path.getPos(0).subtract(newElement.path.getPos(newElement.path.length - 1)).length < strokeWidth * 2) {
                        newElement.path.push(["Z"]);
                        newElement.path.adjustPathAroundAnchor(newElement.path.length - 1);
                        newElement.path.adjustPathAroundAnchor(0);
                        tryIntersection = false;
                    }
                }
            }
        }  // Redraw the path  
        
        
        
        newElement.setAttribute("d", SVGExport.pathCmds(newElement.path));
        svgShape.redraw();
        
        if (tryIntersection) {
            if (!newElement.path.pathIsClosed()) {
                //trace("Path is open, checking against backdrop...");
                intersectPathWithBackdrop();
            }
        }
    }
    
    private function intersectPathWithBackdrop() : Void{
        if (!editor.editingScene())             return  // Find the background shapes  ;
        
        
        
        var fills : Array<Dynamic> = editor.getWorkArea().getBackDropFills();
        
        // Does the path collide with the backdrop shapes?
        var wasUsed : Bool = false;
        for (i in 0...fills.length){
            if (PixelPerfectCollisionDetection.isColliding(svgShape, fills[i])) {
                // Walk path to find intersection points
                wasUsed = wasUsed || handleIntersections(try cast(fills[i], SVGShape) catch(e:Dynamic) null);
            }
        }
        
        if (wasUsed) 
            contentLayer.removeChild(svgShape);
    }
    
    // Get the intersection points of two paths, the indices of the commands adjacent to
    // the intersections and the ratio of the command completion at each intersection
    private function handleIntersections(otherShape : SVGShape) : Bool{
        // The backdrop shape must be closed
        if (!otherShape.getElement().path.getSegmentEndPoints(0)[2])             return false;
        
        if (otherShape.getElement().tag != "path") 
            otherShape.getElement().convertToPath();
        
        var otherSW : Dynamic = otherShape.getElement().getAttribute("stroke-width");
        var otherStr : Dynamic = otherShape.getElement().getAttribute("stroke");
        var otherFill : Dynamic = otherShape.getElement().getAttribute("fill");
        var thisSW : Dynamic = svgShape.getElement().getAttribute("stroke-width");
        var wasUsed : Bool = false;
        
        // Make sure that it isn't just the stroke width that is causing the intersection.
        // We want paths which intersect and not just "touch"
        otherShape.getElement().setAttribute("stroke-width", testWidth);
        otherShape.getElement().setAttribute("stroke", "black");
        otherShape.getElement().setAttribute("fill", "none");
        svgShape.getElement().setAttribute("stroke-width", testWidth);
        otherShape.visible = false;
        otherShape.redraw();
        otherShape.visible = true;
        svgShape.visible = false;
        svgShape.redraw();
        svgShape.visible = true;
        
        var cl : Sprite = editor.getContentLayer();
        //svgShape.debugMode = true;
        svgShape.distCheck = SVGShape.bisectionDistCheck;
        var intersections : Array<Dynamic> = svgShape.getAllIntersectionsWithShape(otherShape);
        
        // Okay, they definitely intersect, let's find out where
        var path : SVGPath = svgShape.getElement().path.clone();
        /*
			for(var j:int=0; j<intersections.length; ++j) {
				var d:Object = intersections[j];
				var str:String = 'Intersection #'+j+':  start ('+d.start.index+', '+d.start.time+')';
				if(d.end) {
					str+= '   end ('+d.end.index+', '+d.end.time+')';
				}
				trace(str);
			}
*/
        //trace("Reverse intersection check");
        svgShape.visible = false;
        svgShape.redraw();
        svgShape.visible = true;
        otherShape.distCheck = SVGShape.bisectionDistCheck;
        var otherIntersections : Array<Dynamic> = otherShape.getAllIntersectionsWithShape(svgShape);
        /*
			for(j=0; j<otherIntersections.length; ++j) {
				d = otherIntersections[j];
				str = 'Intersection #'+j+':  start ('+d.start.index+', '+d.start.time+')';
				if(d.end) {
					str+= '   end ('+d.end.index+', '+d.end.time+')';
				}
				trace(str);
			}
			*/
        
        if (intersections.length == 2) {
            var firstPt : Point = Point.interpolate(path.getPos(intersections[0].start.index, intersections[0].start.time),
                    path.getPos(intersections[0].end.index, intersections[0].end.time), 0.5);
            var secondPt : Point = Point.interpolate(path.getPos(intersections[1].start.index, intersections[1].start.time),
                    path.getPos(intersections[1].end.index, intersections[1].end.time), 0.5);
            /*
				var pos:Point = editor.getContentLayer().globalToLocal(svgShape.localToGlobal(firstPt));
				editor.getContentLayer().graphics.lineStyle(3, 0xFFFF00);
				editor.getContentLayer().graphics.drawCircle(pos.x, pos.y, 10);
				pos = editor.getContentLayer().globalToLocal(svgShape.localToGlobal(secondPt));
				editor.getContentLayer().graphics.lineStyle(3, 0xFF00FF);
				editor.getContentLayer().graphics.drawCircle(pos.x, pos.y, 10);
*/
            var inter : Dynamic = intersections[0];
            var index : Int = inter.start.index;
            var ofs : Int = index - 1;
            if (inter.end && index == inter.end.index) {
                var t : Float = (inter.start.time + inter.end.time) / 2;
                if (path.splitCurve(index, t)) 
                    --ofs;
            }  // Cut off the beginning portion    //var pt:Point = path.getPos(index+1);  
            
            
            
            path.splice(0, index, ["M", firstPt.x, firstPt.y]);
            // If we just truncate the first curve, then put the first control point
            // on the first point.
            path[1][1] = Math.floor(firstPt.x);
            path[1][2] = Math.floor(firstPt.y);
            
            path.adjustPathAroundAnchor(0, 1, 1);
            inter = intersections[1];
            index = inter.start.index - ofs;
            //trace('new index for intersection #1 is '+index);
            if (inter.end && index == (inter.end.index - ofs)) {
                t = (inter.start.time + inter.end.time) / 2;
                path.splitCurve(index, t);
                ++index;
                
                // Cut off the end potion
                path.length = Math.min(index, path.length);
            }
            else {
                ++index;
                path.length = Math.min(index, path.length);
            }
            path.move(path.length - 1, secondPt);
            path[path.length - 1][3] = secondPt.x;
            path[path.length - 1][4] = secondPt.y;
            svgShape.getElement().setAttribute("stroke-linecap", "butt");
            
            if (otherIntersections.length == 2) {
                var firstPath : SVGPath = otherShape.getElement().path.clone();
                var oFirstPt : Point = Point.interpolate(firstPath.getPos(otherIntersections[0].start.index, otherIntersections[0].start.time),
                        firstPath.getPos(otherIntersections[0].end.index, otherIntersections[0].end.time), 0.5);
                var oSecondPt : Point = Point.interpolate(firstPath.getPos(otherIntersections[1].start.index, otherIntersections[1].start.time),
                        firstPath.getPos(otherIntersections[1].end.index, otherIntersections[1].end.time), 0.5);
                /*
					pos = editor.getContentLayer().globalToLocal(otherShape.localToGlobal(oSecondPt));
					editor.getContentLayer().graphics.lineStyle(3, 0xFF0000);
					editor.getContentLayer().graphics.drawCircle(pos.x, pos.y, 10);
*/
                var pathReversed : SVGPath = path.clone();
                pathReversed.reversePath(0);
                if (firstPt.subtract(oFirstPt).length > firstPt.subtract(oSecondPt).length) {
                    //trace("reversed!");
                    var tmp : SVGPath = path;
                    path = pathReversed;
                    pathReversed = tmp;
                    
                    var tmpPt : Point = firstPt;
                    firstPt = secondPt;
                    secondPt = tmpPt;
                }
                
                var startOfEnd : Int = firstPath.splitCurve(otherIntersections[1].end.index, otherIntersections[1].end.time);
                var endOfStart : Int = firstPath.splitCurve(otherIntersections[0].start.index, otherIntersections[0].start.time);
                //trace("Look at index #"+endOfStart+" and #"+startOfEnd);
                //firstPath.outputCommands();
                var deleteCount : Int = startOfEnd - endOfStart + 1;
                var drawnPath : SVGPath = path.clone();
                path.transform(svgShape, otherShape);
                var args : Array<Dynamic> = path.substring(1);
                args.unshift(deleteCount);
                args.unshift(endOfStart + 1);
                var removedCommands : SVGPath = new SVGPath();
                removedCommands.set(firstPath.splice.apply(firstPath, args));
                //trace("moving #"+endOfStart+" to ("+oFirstPt.x+", "+oFirstPt+")");
                firstPath.move(endOfStart, oFirstPt, SVGPath.ADJUST.CORNER);
                //trace("moving #"+(startOfEnd - deleteCount + path.length)+" to ("+oSecondPt.x+", "+oSecondPt+")");
                firstPath.move(startOfEnd - deleteCount + path.length, oSecondPt, SVGPath.ADJUST.CORNER);
                if (firstPath[firstPath.length - 1][0] != "Z") 
                    firstPath.push(["Z"])  //pathReversed.outputCommands();    // Create the second part of the bisected shape    //firstPath.outputCommands();  ;
                
                
                
                
                
                
                removedCommands.transform(otherShape, svgShape);
                pathReversed.push.apply(pathReversed, removedCommands.substring(0));
                if (pathReversed[pathReversed.length - 1][0] != "Z") 
                    pathReversed.push(["Z"])  //pathReversed.outputCommands();  ;
                
                
                var fill1 : SVGShape = (try cast(svgShape.clone(), SVGShape) catch(e:Dynamic) null);
                firstPath.transform(otherShape, svgShape);
                fill1.getElement().path = firstPath;
                fill1.getElement().setAttribute("d", SVGExport.pathCmds(firstPath));
                fill1.getElement().setAttribute("stroke", "none");
                fill1.getElement().setAttribute("fill", otherFill);
                fill1.getElement().setAttribute("scratch-type", "backdrop-fill");
                editor.getWorkArea().addBackdropFill(fill1);
                fill1.redraw();
                
                var fill2 : SVGShape = (try cast(svgShape.clone(), SVGShape) catch(e:Dynamic) null);
                fill2.getElement().path = pathReversed;
                fill2.getElement().setAttribute("d", SVGExport.pathCmds(pathReversed));
                fill2.getElement().setAttribute("stroke", "none");
                fill2.getElement().setAttribute("fill", otherFill);
                fill2.getElement().setAttribute("scratch-type", "backdrop-fill");
                editor.getWorkArea().addBackdropFill(fill2);
                fill2.redraw();
                
                var bisector : SVGShape = (try cast(svgShape.clone(), SVGShape) catch(e:Dynamic) null);
                bisector.getElement().path = drawnPath;
                bisector.getElement().setAttribute("d", SVGExport.pathCmds(drawnPath));
                bisector.getElement().setAttribute("fill", "none");
                bisector.getElement().setAttribute("stroke-width", thisSW);
                bisector.getElement().setAttribute("scratch-type", "backdrop-stroke");
                editor.getWorkArea().addBackdropStroke(bisector);
                bisector.redraw();
                
                contentLayer.removeChild(otherShape);
                wasUsed = true;
            }  /*
				if(otherIntersections.length == 2) {
					var pathCopy:SVGPath = path.clone();
					var pathCopy:SVGPath = path.clone();
				}
*/  
        }  // Return the shapes to their original state  
        
        
        
        otherShape.getElement().setAttribute("stroke", otherStr);
        otherShape.getElement().setAttribute("stroke-width", otherSW);
        otherShape.getElement().setAttribute("fill", otherFill);
        svgShape.getElement().setAttribute("stroke-width", thisSW);
        otherShape.visible = false;
        otherShape.redraw();
        otherShape.visible = true;
        svgShape.visible = false;
        svgShape.redraw();
        svgShape.visible = true;
        
        return wasUsed;
    }
}

