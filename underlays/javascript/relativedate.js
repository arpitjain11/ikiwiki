// Causes html elements in the 'relativedate' class to be displayed
// as relative dates. The date is parsed from the title attribute, or from
// the element content.

var dateElements;

hook("onload", getDates);

function getDates() {
	dateElements = getElementsByClass('relativedate');
	for (var i = 0; i < dateElements.length; i++) {
		var elt = dateElements[i];
		var title = elt.attributes.title;
		var d = new Date(title ? title.value : elt.innerHTML);
		if (! isNaN(d)) {
			dateElements[i].date=d;
			elt.title=elt.innerHTML;
		}
	}

	showDates();
}

function showDates() {
	for (var i = 0; i < dateElements.length; i++) {
		var elt = dateElements[i];
		var d = elt.date;
		if (! isNaN(d)) {
			elt.innerHTML=relativeDate(d);
		}
	}
	setTimeout(showDates,30000); // keep updating every 30s
}

var timeUnits = new Array;
timeUnits['minute'] = 60;
timeUnits['hour'] = timeUnits['minute'] * 60;
timeUnits['day'] = timeUnits['hour'] * 24;
timeUnits['month'] = timeUnits['day'] * 30;
timeUnits['year'] = timeUnits['day'] * 364;
var timeUnitOrder = ['year', 'month', 'day', 'hour', 'minute'];

function relativeDate(date) {
	var now = new Date();
	var offset = date.getTime() - now.getTime();
	var seconds = Math.round(Math.abs(offset) / 1000);

	var ret = "";
	var shown = 0;
	for (i = 0; i < timeUnitOrder.length; i++) {
		var unit = timeUnitOrder[i];
		if (seconds >= timeUnits[unit]) {
			var num = Math.floor(seconds / timeUnits[unit]);
			seconds -= num * timeUnits[unit];
			if (ret)
				ret += "and ";
			ret += num + " " + unit + (num > 1 ? "s" : "") + " ";

			if (++shown == 2)
				break;
		}
		else if (shown)
			break;
	}

	if (! ret)
		ret = "less than a minute "

	return ret + (offset < 0 ? "ago" : "from now");
}
