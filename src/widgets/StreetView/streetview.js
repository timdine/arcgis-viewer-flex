////////////////////////////////////////////////////////////////////////////////
////																		////
////				street view specific events								////
////																		////
////////////////////////////////////////////////////////////////////////////////
var panorama;
var streetviewHeight=250;

function initialize_container()
{
	//alert('Container Initialized');
	// create container
	var obj= getSWF("agsview3");
	obj.height = getPageHeight() - streetviewHeight;
	
	var svh = streetviewHeight + "px";
	var divTag = document.createElement("div");                
	divTag.id = "pano";                
	divTag.style.width = "100%";
	divTag.style.height = svh;
	divTag.style.position = "absolute";
	divTag.style.bottom = "0px";
	divTag.style.right = "0px";
	divTag.style.left = "0px"
	document.body.appendChild(divTag);
	addEvent(window, "resize", windowResized ); 

}
function initialize_streetview(long,lat,head)
{
	try{
	    var loc = new google.maps.LatLng(long,lat);
	    var panoramaOptions = {
	    	position: loc,
	    	pov: {
	      	heading:head,
	      	pitch:0,
	      	zoom:1
	    	}};
	    
	    if (document.getElementById("pano"))
	    {
	    	panorama = new google.maps.StreetViewPanorama(document.getElementById("pano"),panoramaOptions);	
	     	google.maps.event.addListener(panorama, 'position_changed', position_changed);
	      	google.maps.event.addListener(panorama, 'pov_changed', pov_changed);
	    }
	     	
	}catch(err){
		alert(err + "\n" + "Is here");	
	}
	
}
function position_changed()
{
	var pt = panorama.getPosition();
	var head = panorama.getPov().heading
	var obj= getSWF("agsview3");
	obj.theFlexFunction(pt.lat(),pt.lng(),head);
}
function pov_changed()
{
	var pt = panorama.getPosition();
	var head = panorama.getPov().heading
	var obj= getSWF("agsview3");
	obj.theFlexFunction(pt.lat(),pt.lng(),head);
}
function removeStreetview()
{
	try{
		var theDiv = document.getElementById("pano");
		if(theDiv!=null)
		{
			document.body.removeChild(theDiv);	
			theDiv=null;
			panorama = null;
			var obj= getSWF("agsview3");
			obj.height = "100%";
		}
    }catch(err){
		alert(err);
	}
}
function restoreStreetview()
{
	try
	{
		var theDiv = document.getElementById("pano");
		if(theDiv!=null)
		{
			var obj= getSWF("agsview3");
			obj.height = getPageHeight() - streetviewHeight;
			theDiv.style.display = "block";
		}
	}catch(err){
	}
}
function minimizeStreetview()
{
	try
	{
		var theDiv = document.getElementById("pano");
		if(theDiv!=null)
		{
			var obj= getSWF("agsview3");
			obj.height = "100%";
			theDiv.style.display = "none";
		}	
	}catch(err){
		alert(err);
	}
}
////////////////////////////////////////////////////////////////////////////////
////																		////
////				default page events										////
////																		////
////////////////////////////////////////////////////////////////////////////////
var addEvent = function(elem, type, eventHandle) { 
    if (elem == null || elem == undefined) return; 
    if ( elem.addEventListener ) { 
        elem.addEventListener( type, eventHandle, false ); 
    } else if ( elem.attachEvent ) { 
        elem.attachEvent( "on" + type, eventHandle ); 
    } 
}; 
function getSWF(swfName) {
	if (navigator.appName.indexOf("Microsoft") != -1) {
		return window[swfName];
	}
	else{
		if(document[swfName].length != undefined){
			return document[swfName][1];
		}
	return document[swfName];
	}
}
function getPageHeight()
{
	var vpHeight;
	if (typeof window.innerHeight != 'undefined')
	{
		vpHeight = window.innerHeight;
	}
	else if (typeof document.documentElement != 'undefined' && typeof document.documentElement.clientWidth != 'undefined' && document.documentElement.clientWidth != 0 )
	{	
		vpHeight = document.documentElement.clientHeight;
	}
	else
	{
		vpHeight = document.getElementsByTagName('body')[0].clientHeight;
	}
	return vpHeight;
}
function windowResized()
{
	try{
		if(panorama!=null){
			var theDiv = document.getElementById("pano");
			if(theDiv!=null)
			{
				if (theDiv.style.display != "none")
				{
					var obj= getSWF("agsview3");
					obj.height = getPageHeight() - streetviewHeight;
					//panorama.checkResize();
				}
			}
		}	
	}catch(err){
	}
}