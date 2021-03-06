package {

  import flash.display.Stage;
  import flash.display.StageAlign;
  import flash.display.StageScaleMode;
  import flash.display.StageQuality;
  import flash.display.Sprite;
  import flash.events.Event;
  import flash.events.MouseEvent;
  import flash.system.Security;


  /**
   * The ZeroClipboard class creates a simple Sprite button that will put
   * text in the user's clipboard when clicked.
   */
  [SWF(widthPercent="100%", heightPercent="100%", backgroundColor="#FFFFFF")]
  public class ZeroClipboard extends Sprite {

    /**
     * ZeroClipboard library version number at the time this SWF was compiled.
     */
    public static const VERSION:String = "<%= version %>";


    /**
     * Function through which JavaScript events are emitted. Accounts for scenarios
     * in which ZeroClipboard is used via AMD/CommonJS module loaders, too.
     */
    private var jsEmitter:String = null;

    /**
     * JavaScript proxy object.
     */
    private var jsProxy:JsProxy = null;

    /**
     * Clipboard proxy object.
     */
    private var clipboard:ClipboardInjector = null;


    /**
     * @constructor
     */
    public function ZeroClipboard() {
      // The JIT Compiler does not compile constructors, so ANY
      // cyclomatic complexity higher than 1 is discouraged.
      this.ctor();
    }


    /**
     * The real constructor.
     *
     * @return `undefined`
     */
    private function ctor(): void {
      // If the `stage` is available, begin!
      if (stage) {
        this.init();
      }
      else {
        // Otherwise, wait for the `stage`....
        this.addEventListener(Event.ADDED_TO_STAGE, this.init);
      }
    }


    /**
     * Initialize the class when the Stage is ready.
     *
     * @return `undefined`
     */
    private function init(): void {
      // Remove the event listener, if any
      this.removeEventListener(Event.ADDED_TO_STAGE, this.init);

      // Establish a communication line with JavaScript
      this.jsProxy = new JsProxy();

      // Collect the real FlashVars
      var expectedFlashVars:Object;  // NOPMD
      expectedFlashVars = this.getExpectedFlashVars();

      // Allow the SWF object to communicate with a page on a different origin than its own (e.g. SWF served from CDN)
      Security.allowDomain.apply(Security, expectedFlashVars.trustedOrigins);

      var jsProxyObjectId:String = this.jsProxy.getObjectId();
      var expectedObjectId:String = expectedFlashVars.swfObjectId;

      this.jsEmitter =
        "(function(eventObj) {\n" +
        "  var objectId = '" + jsProxyObjectId + "',\n" +
        "      swf = document[objectId] || document.getElementById(objectId),\n" +
        "      ZC, result;\n\n" +
        "  if (swf && typeof swf.ZeroClipboard === 'function' && typeof swf.ZeroClipboard.emit === 'function') {\n" +
        "    ZC = swf.ZeroClipboard;\n" +
        "  }\n" +
        "  else if (typeof ZeroClipboard === 'function' && typeof ZeroClipboard.emit === 'function') {\n" +
        "    ZC = ZeroClipboard;\n" +
        "  }\n" +
        "  // Drop the element reference, if any\n" +
        "  swf = null;\n" +
        "  if (!ZC) {\n" +
        "    throw new Error('ERROR: ZeroClipboard SWF could not locate ZeroClipboard JS object!\\n" +
                             "Expected element ID: ' + objectId);\n" +
        "  }\n\n" +
        "  result = ZC.emit(eventObj);\n\n" +
        "  // Drop the reference\n" +
        "  ZC = null;\n\n" +
        "  return result;\n" +
        "})";

      // Create an invisible "button" and transparently fill the entire Stage
      var button:Sprite = this.prepareUI();

      // Configure the clipboard injector
      this.clipboard = new ClipboardInjector(expectedFlashVars.forceEnhancedClipboard);

      // Only proceed if this SWF is hosted in the browser as expected
      if (!this.jsProxy.isComplete()) {
        // Signal to the browser that something is wrong
        this.emit("error", {
          name: "flash-unavailable"
        });
      }
      else if (!this.jsProxy.isHighFidelity()) {
        // Signal to the browser that data fidelity cannot be guaranteed
        this.emit("error", {
          name: "flash-degraded"
        });
      }
      else if (!expectedFlashVars.jsVersion || !ZeroClipboard.VERSION || expectedFlashVars.jsVersion !== ZeroClipboard.VERSION) {
        this.emit("error", {
          name: "version-mismatch",
          jsVersion: expectedFlashVars.jsVersion || null,
          swfVersion: ZeroClipboard.VERSION || null
        });
      }
      else if (!expectedObjectId || jsProxyObjectId !== expectedObjectId) {
        // Signal to the browser that the expected ID does not match the actual ID
        this.emit("error", {
          name: "config-mismatch",
          property: "swfObjectId",
          configuredValue: expectedObjectId || null,
          actualValue: jsProxyObjectId || null
        });
      }
      else {
        // Add the MouseEvent listeners
        this.addMouseHandlers(button);

        // Expose the external functions
        this.jsProxy.addCallback(
          "setHandCursor",
          function(enabled:Boolean): void {
            button.useHandCursor = enabled === true;
          }
        );

        // Signal to the browser that we are ready
        this.emit("ready", {
          swfVersion: ZeroClipboard.VERSION
        });
      }
    }


    /**
     * Get an accurate interpretation of the FlashVars for this SWF instance.
     *
     * IMPORTANT: This also serves the double purpose of reestablishing the correct FlashVars when
     * the SWF is retrieved from the browser cache but originally hosted on an external domain.
     *
     * @return Object
     */
    private function getFlashVarsFromHtml(
    ): Object {  // NOPMD
      var flashVars:Object = null;  // NOPMD

      if (this.jsProxy && this.jsProxy.isComplete() && this.jsProxy.isHighFidelity()) {
        var rawFlashVars:String = this.jsProxy.call(
          "(function() {\n" +
          "  var objectId = '" + this.jsProxy.getObjectId() + "',\n" +
          "      swf = document[objectId] || document.getElementById(objectId),\n" +
          "      result, i, len, paramEl;\n\n" +
          "  if (swf && swf.nodeName === 'OBJECT') {\n" +
          "    for (i = 0, len = swf.children.length; i < len; i++) {\n" +
          "      paramEl = swf.children[i];\n" +
          "      if (paramEl && paramEl.nodeName === 'PARAM' && (paramEl.getAttribute('name') || '').toLowerCase() === 'flashvars') {\n" +
          "        result = paramEl.getAttribute('value') || null;\n" +
          "      }\n" +
          "    }\n" +
          "  }\n\n" +
          "  // Drop the element references, if any\n" +
          "  swf = paramEl = null;\n\n" +
          "  return result;\n" +
          "})"
        );

        flashVars = rawFlashVars ? XssUtils.sanitize(XssUtils.parseQuery("?" + rawFlashVars)) : null;
      }

      return flashVars;
    }


    /**
     * Retrieve and transform (or default) the expected FlashVars values.
     *
     * @return Object
     */
    private function getExpectedFlashVars(
    ): Object { // NOPMD
      var expectedFlashVars:Object;  // NOPMD
      expectedFlashVars = {
        swfObjectId: "global-zeroclipboard-flash-bridge",
        trustedOrigins: [],
        forceEnhancedClipboard: false,
        jsVersion: null
      };

      // Get the FlashVars
      var flashVars:Object;  // NOPMD
      flashVars = this.getFlashVarsFromHtml() || {};

      // Configure the SWF object's ID
      if (flashVars.swfObjectId && typeof flashVars.swfObjectId === "string") {
        var swfId:String = flashVars.swfObjectId;

        // Validate the ID against the HTML4 spec for `ID` tokens.
        if (XssUtils.isValidHtmlId(swfId)) {
          expectedFlashVars.swfObjectId = swfId;
        }
      }

      // Allow the SWF object to communicate with a page on a different origin than its own (e.g. SWF served from CDN)
      if (flashVars.trustedOrigins && typeof flashVars.trustedOrigins === "string") {
        expectedFlashVars.trustedOrigins = flashVars.trustedOrigins.split(",");
      }

      // Enable use of the fancy "Desktop" clipboard, even on Linux where it is known to suck
      if (flashVars.forceEnhancedClipboard === "true" || flashVars.forceEnhancedClipboard === true) {
        expectedFlashVars.forceEnhancedClipboard = true;
      }

      // Get the version number of the ZeroClipboard JS side of the library
      if (typeof flashVars.jsVersion === "string") {
        expectedFlashVars.jsVersion = flashVars.jsVersion;
      }

      return expectedFlashVars;
    }


    /**
     * Prepare the Stage and Button.
     *
     * @return Button
     */
    private function prepareUI(): Sprite {
      // Set the stage!
      stage.align = StageAlign.TOP_LEFT;
      stage.scaleMode = StageScaleMode.EXACT_FIT;
      stage.quality = StageQuality.BEST;

      // Create an invisible "button" and transparently fill the entire Stage
      var button:Sprite = new Sprite();
      button.graphics.beginFill(0xFFFFFF);
      button.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
      button.alpha = 0.0;

      // Act like a button. This includes:
      //  - Showing a hand cursor by default
      //  - Receiving click events
      //  - Receiving keypress events of space/"Enter" as click
      //    events IF AND ONLY IF the Sprite is focused.
      button.buttonMode = true;

      // Override the hand cursor default
      button.useHandCursor = false;

      // Add the invisible "button" to the stage!
      this.addChild(button);

      // Return the button for adding event listeners
      return button;
    }


    /**
     * Clears the clipboard and sets new clipboard text. It gets this from the "_clipData"
     * variable on the JavaScript side. Once the text has been placed in the clipboard, it
     * then signals to the JavaScript that it is done.
     *
     * @return `undefined`
     */
    private function onClick(event:MouseEvent): void {
      var clipData:Object;  // NOPMD
      var clipInjectResults:Object = {};  // NOPMD

      // Allow for any "UI preparation" work before the "copy" event begins
      this.emit("beforecopy");

      // Request pending clipboard data from the page
      clipData = this.emit("copy");

      // Inject all pending data into the user's clipboard
      clipInjectResults = this.clipboard.inject(clipData);

      // Compose and serialize a results object, send it back to the page
      this.emit(
        "aftercopy",
        {
          success: clipInjectResults.success,
          data: clipData,
          errors: clipInjectResults.errors
        }
      );
    }


    /**
     * Emit events to JavaScript.
     *
     * @return `undefined`, or the new "_clipData" object
     */
    private function emit(
      eventType:String,
      eventObj:Object = null  // NOPMD
    ): Object {  // NOPMD
      if (eventObj == null) {
        eventObj = {};
      }
      eventObj.type = eventType;

      var result:Object = undefined;  // NOPMD
      if (this.jsProxy.isComplete()) {
        result = this.jsProxy.call(this.jsEmitter, eventObj);
      }
      else {
        this.jsProxy.send(this.jsEmitter, eventObj);
      }
      return result;
    }


    /**
     * Signals to the page that a MouseEvent occurred.
     *
     * @return `undefined`
     */
    private function onMouseEvent(event:MouseEvent): void {
      var evtData:Object = {}; // NOPMD

      // If an event is passed in, return what modifier keys are pressed, etc.
      if (event) {
        var props:Object;  // NOPMD
        props = {
          "altKey": "altKey",
          "commandKey": "metaKey",
          "controlKey": "ctrlKey",
          "shiftKey": "shiftKey",
          "clickCount": "detail",
          "movementX": "movementX",
          "movementY": "movementY",
          "stageX": "_stageX",
          "stageY": "_stageY"
        };

        for (var prop:String in props) {
          if (event.hasOwnProperty(prop) && event[prop] != null) {
            evtData[props[prop]] = event[prop];
          }
        }
        evtData.type = "_" + event.type.toLowerCase();
        evtData._source = "swf";
      }

      this.emit(evtData.type, evtData);
    }


    /**
     * Add mouse event handlers to the button.
     *
     * @return `undefined`
     */
    private function addMouseHandlers(button:Sprite): Sprite {
      button.addEventListener(MouseEvent.MOUSE_MOVE, this.onMouseEvent);
      button.addEventListener(MouseEvent.MOUSE_OVER, this.onMouseEvent);
      button.addEventListener(MouseEvent.MOUSE_OUT, this.onMouseEvent);
      button.addEventListener(MouseEvent.MOUSE_DOWN, this.onMouseEvent);
      button.addEventListener(MouseEvent.MOUSE_UP, this.onMouseEvent);
      button.addEventListener(MouseEvent.CLICK, this.onClick);
      button.addEventListener(MouseEvent.CLICK, this.onMouseEvent);
      return button;
    }
  }
}
