/**
  FlexiCAM Viper post processor
  Made by kenc@kea.dk & andh@kea.dk
  Date: 2019-05-16
  Version 4
*/

description = "FlexiCAM Viper";
vendor = "FlexiCAM";
vendorUrl = "http://www.flexicam.com";
legal = "Copyright (C) 2012-2015 by Autodesk, Inc.";
certificationLevel = 2;

longDescription = "Milling post for FlexiCAM Viper.";

extension = "DIN";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);
minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion

// user-defined properties
properties = {
  keepVacuumON: true, // write machine
  pauseMachine: true, // write machine
  writeMachine: true, // write machine
  writeTools: true, // writes the tools
  separateWordsWithSpace: true // specifies that the words should be separated with a white space
};

// user-defined property definitions
propertyDefinitions = {
  keepVacuumON: { title: "Keep vacuum suction ON", description: "Keep vacuum suctipon on after the job is finished.", group: 0, type: "boolean" },
  pauseMachine: { title: "Pause at tool change", description: "Pause at tool change.", group: 0, type: "boolean" },
  writeMachine: { title: "Write machine", description: "Output the machine settings in the header of the code.", group: 0, type: "boolean" },
  writeTools: { title: "Write tool list", description: "Output a tool list in the header of the code.", group: 0, type: "boolean" },
  separateWordsWithSpace: { title: "Separate words with space", description: "Adds spaces between words if 'yes' is selected.", type: "boolean" }
};

var numberOfToolSlots = 6;

var WARNING_WORK_OFFSET = 0;
var WARNING_COOLANT = 1;

var gFormat = createFormat({ prefix: "G", decimals: 0 });
var mFormat = createFormat({ prefix: "M", decimals: 0 });
var hFormat = createFormat({ prefix: "H", decimals: 0 });
var dFormat = createFormat({ prefix: "D", decimals: 0 });

var xyzFormat = createFormat({ decimals: (unit == MM ? 3 : 4) });
var zFormat = createFormat({ decimals: (unit == MM ? 3 : 4), scale: 1 });
var abcFormat = createFormat({ decimals: 3, forceDecimal: true, scale: DEG });
var feedFormat = createFormat({ decimals: (unit == MM ? 1 : 2) });
var toolFormat = createFormat({ decimals: 0 });
var rpmFormat = createFormat({ decimals: 0 });
var secFormat = createFormat({ decimals: 3, forceDecimal: true }); // seconds - range 0.001-1000
var taperFormat = createFormat({ decimals: 1, scale: DEG });

var xOutput = createVariable({ prefix: "X" }, xyzFormat);
var yOutput = createVariable({ prefix: "Y" }, xyzFormat);
var zOutput = createVariable({ prefix: "Z" }, zFormat);
var feedOutput = createVariable({ prefix: "F" }, feedFormat);
var sOutput = createVariable({ prefix: "E", force: true }, rpmFormat);
var dOutput = createVariable({}, dFormat);

// circular output
//var iOutput = createReferenceVariable({prefix:"I"}, xyzFormat);
//var iOutput = createVariable({prefix:"I"}, xyzFormat);
// var jOutput = createReferenceVariable({prefix:"J"}, xyzFormat);
//var jOutput = createVariable({prefix:"J"}, xyzFormat);
//var kOutput = createReferenceVariable({prefix:"K"}, zFormat);
//var kOutput = createVariable({prefix:"K"}, xyzFormat);
//var rOutput = createReferenceVariable({prefix:"R"}, zFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({ onchange: function () { gMotionModal.reset(); } }, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gFeedModeModal = createModal({}, gFormat); // modal group 5 // 94
var gUnitModal = createModal({}, gFormat); // modal group 6 // G70-71
// collected state


//Writes the specified block.
function writeBlock() {
  writeWords(arguments);
}

function txt(prefix, number) {
  return prefix + Number(number).toFixed(3);
}

//Output a comment.
function writeComment(text) {
  writeln("(" + text + ")");
}

function onOpen() {
  if (!properties.separateWordsWithSpace)
    setWordSeparator("");

  writeln("%" + (parseFloat(programName) ? programName : 1000));

  if (programComment)
    writeComment(programComment);

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor)
      writeComment("  " + localize("vendor") + ": " + vendor);
    if (model)
      writeComment("  " + localize("model") + ": " + model);
    if (description)
      writeComment("  " + localize("description") + ": " + description);
  }

  // dump tool information
  if (properties.writeTools) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + "  " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + zFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }

  writeBlock("G17");
  writeBlock("G90");
  // writeBlock("M127");
  // writeBlock("M129");
  // writeBlock("G1");
  writeBlock("S1");
  writeBlock("M110");
  writeBlock("M112");
  writeBlock("M120");
  writeBlock("M104");
  writeBlock("M127");
  // writeBlock("M123");
  // writeBlock("M144");
  // writeBlock("M146");
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onParameter(name, value) {
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);

  var retracted = false; // specifies that the tool has been retracted to the safe plane
  if (isFirstSection() || insertToolCall) {
    // retract to safe plane
    retracted = true;
    //writeBlock(gAbsIncModal.format(90));
    zOutput.reset();
  }

  if (insertToolCall) {
    retracted = true;

    if (tool.number > numberOfToolSlots) {
      warning(localize("Tool number exceeds maximum value."));
    }

    if (!isFirstSection()) {
      writeBlock("M101");
      writeBlock("M5");
      writeBlock("M123");
      if (properties.pauseMachine) {
        writeBlock("M1");
      }
    }

    writeBlock("M6 T" + toolFormat.format(tool.number));
    if (tool.comment) {
      writeComment(tool.comment);
    }
    var showToolZMin = false;

    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }
  }

  if (insertToolCall ||
    isFirstSection() ||
    (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) ||
    (tool.clockwise != getPreviousSection().getTool().clockwise)) {
    if (tool.spindleRPM < 1) {
      error(localize("Spindle speed out of range."));
    }
    if (tool.spindleRPM > 99999) {
      warning(localize("Spindle speed exceeds maximum value."));
    }

    writeBlock("M122");
    writeBlock("M3 " + sOutput.format(tool.spindleRPM));
    validate(tool.clockwise);
  }

  // wcs

  if (currentSection.workOffset != 0)
    warningOnce(localize("Work offset is not supported."), WARNING_WORK_OFFSET);

  forceXYZ();

  if (tool.coolant != COOLANT_OFF)
    warningOnce(localize("Coolant not supported."), WARNING_COOLANT);

  forceAny();

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z)
      writeBlock("G00", zOutput.format(initialPosition.z));
  }

  if (insertToolCall) {
    gMotionModal.reset();
    //writeBlock(gPlaneModal.format(17));
    writeBlock("G00", xOutput.format(initialPosition.x), yOutput.format(initialPosition.y));
    writeBlock("G00", zOutput.format(initialPosition.z));
  } else {
    writeBlock(gAbsIncModal.format(90), "G00", xOutput.format(initialPosition.x), yOutput.format(initialPosition.y));
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock("G04", "X" + secFormat.format(seconds));
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(sOutput.format(spindleSpeed));
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    }
    writeBlock("G00", x, y, z);
    feedOutput.reset();
  }
}


function onLinear(_x, _y, _z, feed) {
  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      var d = tool.diameterOffset;
      if (d > numberOfToolSlots) {
        warning(localize("The diameter offset exceeds the maximum value."));
      }
      writeBlock(gPlaneModal.format(17));
      switch (radiusCompensation) {
        case RADIUS_COMPENSATION_LEFT:
          dOutput.reset();
          writeBlock("G01", "G41", x, y, z, dOutput.format(d), f);
          break;
        case RADIUS_COMPENSATION_RIGHT:
          dOutput.reset();
          writeBlock("G01", "G42", x, y, z, dOutput.format(d), f);
          break;
        default:
          writeBlock("G01", "G40", x, y, z, f);
      }
    } else {
      writeBlock("G01", x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock("G01", f);
    }
  }
}


function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (isHelical()) {
    var t = tolerance;
    if (hasParameter("operation:tolerance"))
      t = getParameter("operation:tolerance");

    linearize(t);
    return;
  }

  // one of X/Y and I/J are required and likewise

  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gPlaneModal.format(17));
      writeBlock(clockwise ? "G02" : "G03", xOutput.format(x), yOutput.format(y), zOutput.format(z), txt("I", cx - start.x), txt("J", cy - start.y), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gPlaneModal.format(18));
      writeBlock(clockwise ? "G02" : "G03", xOutput.format(x), yOutput.format(y), zOutput.format(z), txt("I", cx - start.x), txt("K", cz - start.z), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gPlaneModal.format(19));
      writeBlock(clockwise ? "G02" : "G03", xOutput.format(x), yOutput.format(y), zOutput.format(z), txt("J", cy - start.y), txt("K", cz - start.z), feedOutput.format(feed));
      break;
    default:
      var t = tolerance;
      if (hasParameter("operation:tolerance")) {
        t = getParameter("operation:tolerance");
      }
      linearize(t);
  }

  //G03 X234.43 Y405.91 R132.978

  // writeComment("---")
  // writeComment(cx)
  // writeComment(start.x)
  // writeComment(cx - start.x)
  // writeBlock(clockwise ? "G02" : "G03", xOutput.format(x), yOutput.format(y), zOutput.format(- z), rOutput.format(cx - start.x, 0), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));

}

var mapCommand = {
  COMMAND_END: 2
};

function onCommand(command) {
  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  //writeBlock(gPlaneModal.format(17));
  forceAny();
}

function onClose() {
  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  
  if (properties.keepVacuumON) {
    writeBlock("M110");
  } else {
    writeBlock("M111");
  }

  writeBlock("M101");
  writeBlock("M5");
  writeBlock("M123");
  writeBlock("M121");
  writeBlock("M113");
  writeBlock("M105");
  writeBlock("M105");
  writeBlock("M30");
}