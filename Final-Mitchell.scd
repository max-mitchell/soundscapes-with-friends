(


// STEP ONE
//   Run Nodejs server
//   'node osc-control.js -r REMOTE_IP -t CUSTOM_TAG'

// STEP TWO
//   Click below this line and type Ctr-Enter
//   (Or select all with Ctr-A and then type Shift-Enter)











// Makes GUI
~makeGui = {
	// Reboot the server everytime the GUI gets remade
	s.reboot;
	// Once that's done...
	s.doWhenBooted({
		// Run all init code
		~globalInit.value();

		// Create main window
		Window.closeAll;
		~gui = Window("",
			Rect(Window.screenBounds.width - 420,
				Window.screenBounds.height - 320,
				400,
				675)
		).front;

		// Create a master layout
		~gui.view.decorator_(FlowLayout(~gui.bounds, 0@0, 0@0));

		// Top layout holds IP text
		~gui_top_view = CompositeView(~gui, ~gui.bounds.width@50);
		~gui_top_view.decorator_(FlowLayout(~gui_top_view.bounds, 0@5, 0@0));

		// Buttons layout holds reset, send, and stop buttons
		~gui_buttons_view = CompositeView(~gui, 300@230);
		~gui_buttons_view.decorator_(FlowLayout(~gui_buttons_view.bounds, 10@10, 15@15));

		// Meter layout holds meter
		~gui_meter_view = CompositeView(~gui, (~gui.bounds.width * 0.2)@230);
		~gui_meter_view.decorator_(FlowLayout(~gui_meter_view.bounds, 5@5, 5@5));

		// Public IP text box
		~gui_ip_text = StaticText(~gui_top_view, ~gui_top_view.bounds.width@20)
		.string_("Node server not running...")
		.align_(\center);

		// Remote IP text box
		~gui_remote_text = StaticText(~gui_top_view, ~gui_top_view.bounds.width@20)
		.string_("No remote...")
		.align_(\center);

		// Init and reset Pdefs button.
		// Once pressed, the init state is
		// not shown again
		~gui_bt_pdef = Button(~gui_buttons_view, 150@100)
		.states_([
			["Accept\nConnections", Color.black, Color.grey(0.8)],
			["Reset Audio\nServer", Color.black, Color.grey(0.8)]
		])
		.action_({
			arg obj;
			~makeListeners.value();
			if (obj.value == 0, {
				~gui_bt_pdef.value_(1);
			});
		})
		.font_(Font.monospace(20));

		// Mini layout to hold send, stop buttons
		~gui_send_view = CompositeView(~gui_buttons_view, 100@100);
		~gui_send_view.decorator_(FlowLayout(~gui_send_view.bounds, 0@0, 15@15));

		// Tells node to send data
		~gui_bt_send = Button(~gui_send_view, 100@40)
		.states_([
			["Send", Color.black, Color.grey(0.8)]
		])
		.action_({
			~setSendMsg.value(1);
		})
		.font_(Font.monospace(20));

		// Tells node to stop sending data
		~gui_bt_stop = Button(~gui_send_view, 100@40)
		.states_([
			["Stop", Color.black, Color.grey(0.8)]
		])
		.action_({
			~setSendMsg.value(0);
		})
		.font_(Font.monospace(20));

		// Text displaying node status.
		// This is set by the node server, not
		// by the send/stop buttons
		~gui_status = StaticText(~gui_buttons_view, 270@80)
		.string_("Status: Stopped")
		.background_(Color.red(0.8))
		.align_(\center)
		.font_(Font.monospace(20));

		// Server level meter
		~gui_lvl = ServerMeterView(s, ~gui_meter_view, 0@0, 0, 2);

		// Label for message section
		~gui_incoming_text = StaticText(~gui, ~gui.bounds.width@40)
		.string_("Incoming messages")
		.align_(\center)
		.font_(Font.monospace(25));

		// Layout for the incoming messages.
		// Uses a grid, use vRowMax and vColMax below
		// to set the max rows and cols
		~gui_incoming_view = CompositeView(~gui, ~gui.bounds.width@350);
		~gui_incoming_view.layout_(GridLayout());

		// Get public and remote IP to
		// set top text
		~getPubIP.value();
	})
};

// Make GUI
~makeGui.value();

// Set incoming grid rows and cols
~vColMax = 2;
~vRowMax = 3;

// Set max connections at once
~maxMsgIn = ~vColMax * ~vRowMax;


~globalInit = {
	Buffer.freeAll;

	// Load perc samples into a dict
	// Samples are in four catagories
	//   Crashes and Symbols
	//   Low hits
	//   Medium hits
	//   High hits
	~percD = Dictionary.new;
	~percD.add(\lows ->
		PathName(thisProcess.nowExecutingPath.dirname +/+ "lows").files.collect({
			arg sf;
			Buffer.read(s, sf.fullPath);
		});
	);
	~percD.add(\mids ->
		PathName(thisProcess.nowExecutingPath.dirname +/+ "mids").files.collect({
			arg sf;
			Buffer.read(s, sf.fullPath);
		});
	);
	~percD.add(\highs ->
		PathName(thisProcess.nowExecutingPath.dirname +/+ "highs").files.collect({
			arg sf;
			Buffer.read(s, sf.fullPath);
		});
	);
	~percD.add(\crash ->
		PathName(thisProcess.nowExecutingPath.dirname +/+ "crash").files.collect({
			arg sf;
			Buffer.read(s, sf.fullPath);
		});
	);

	// Set quant time to 4/4 @ 120 bpm
	~time = 60/120 * 4;

	// Load buffer playback synth
	SynthDef.new(\bufplay,{
		arg out=0, buf=0, rate=1, amp=0.8, precision=23, pan=0;
		var sig, delay;
		sig = PlayBuf.ar(1, buf, BufRateScale.ir(buf) * rate, doneAction: 2);
		sig = Pan2.ar(sig, pan, amp);
		sig = MantissaMask.ar(sig, precision);
		Out.ar(out, sig);
	}).add;

	// Load sine generator synt
	SynthDef.new(\sine, {
		arg out, freq=220, atk=0.5, rel=0.5, amp=0.5, pan=0, precision=23;
		var env, sig, delay;
		sig = SinOsc.ar(freq);
		env = EnvGen.kr(Env.new([0, 1, 0], [atk, rel], [1, -1]), doneAction: 2);
		sig = Pan2.ar(sig, pan, amp);
		sig = sig * env;
		sig = MantissaMask.ar(sig, precision);
		Out.ar(out, sig);
	}).add;

	// Load reverb fx synth
	SynthDef.new(\reverb, {
		arg out=0, in, roomSize=0;
		var sig;
		sig = In.ar(in, 2);
		sig = FreeVerb.ar(sig, roomSize, roomSize, roomSize);
		Out.ar(out, sig);
	}).add;

	// Load limiter
	// One goes at the end to make sure there
	// is no clipping
	SynthDef.new(\limiter, {
		arg out=0, in;
		var sig;
		sig = In.ar(in, 2);
		sig = Limiter.ar(sig, 0.7, 0.01);
		Out.ar(out, sig);
	}).add;

	// Create busses for the limiter
	~limiterIn = Bus.audio(s, 2);

	// Create sound groups
	~srcGrp = Group.head;
	~revGrp = Group.tail;
	~limGrp = Group.tail;

	// Create dict for patterns
	~patD = Dictionary.new;

	// Create dict for incomming messages
	~viewD = Dictionary.new;

	// Set OSC out path
	~addr = NetAddr.new("localhost", 57121);

	// Make listener for ip fetch
	OSCdef(
		\setPubIP,
		{
			arg msg, time, addr, recvPort;
			{
				~gui_ip_text.string_("Your public IP is "++msg[1].asString);
				~gui_remote_text.string_("Sending data to "++msg[2].asString);
			}.defer;
		},
		"/setPubIP"
	);

	// Make listener for server sending status
	OSCdef(
		\isSending,
		{
			arg msg, time, addr, recvPort;
			if (msg[1] == 1, {
				{
					~gui_status.string_("Status: Sending").background_(Color.green(0.8));
				}.defer;
			},
			{
				{
					~gui_status.string_("Status: Stopped").background_(Color.red(0.8));
				}.defer;
			}
			);
		},
		"/isSending"
	);
};

// Fetch public IP's from Node
~getPubIP = {
	~addr.sendMsg("/getPubIP");
};

// Start or stop sending messages
~setSendMsg = {
	arg send;
	~addr.sendMsg("/doSend", send);
};

// Start listening for messages,
// create patterns in response
~makeListeners = {
	Pdef.removeAll;
	~revGrp.freeAll;
	~limGrp.freeAll;

	~gui_incoming_view.children.collect(_.remove);
	~gui_incoming_view.decorator.reset;

	~vCol = 0;
	~vRow = 0;

	Synth.new(\limiter, [\in, ~limiterIn], ~limGrp, \addToTail);

	~panChoose = Pseq([1, -1], inf).asStream;

	~patD = Dictionary.new;
	~viewD = Dictionary.new;

	~diffArrayLen = 20;

	// Stop listener
	OSCdef(
		\stop,
		{
			arg msg, time, addr, recvPort;
			var tag;

			// Grab tag from message
			tag = msg[1].asString;

			// If the tag is good...
			if (~patD.includesKey(tag), {
				// Stop the pdefs
				~patD[tag][4].stop;
				~patD[tag][5].stop;

				// Leave the reverb in to fade out

				// Remove the key from the dict
				~patD.removeAt(tag);

				// Remove view object
				{
					~viewD[tag].remove;
					~viewD.removeAt(tag);
				}.defer;

				("Sender shutoff -> "++tag).postln;
			});
		},
		"/stop"
	);

	// OSC listener
	OSCdef(
		\time,
		{
			arg msg, time, addr, recvPort;
			var night, precision, timeDiff, diffMax, dur, weights, base, roomSize, atkRaw, relRaw, percRate, tag;

			// Get message time delay
			timeDiff = Date.localtime.rawSeconds.asFloat - msg[1].asFloat;

			// Get tag from message
			tag = msg[5].asString;

			// Lookup tag to see if any new
			// synths or pdefs have to be created
			if (~patD.includesKey(tag).not, {
				var pan, bus, rtag, stag;

				pan = 0.4.rrand(1.0) * ~panChoose.next;
				bus = Bus.audio(s, 2);

				rtag = tag++"r";
				stag = tag++"s";

				~patD.add(tag -> Array.with(
					// Delay index [0]
					0,

					// Max delay time [1]
					0,

					// Delay array [2]
					Array.fill(~diffArrayLen, { arg i; 0.015 }),

					// Reverb synth [3]
					Synth.new(\reverb,
						[\in, bus, \out, ~limiterIn],
						~revGrp,
						\addToTail),

					// Rhythm pdef [4]
					Pdef(rtag,
						Pbind(
							\instrument, \bufplay,
							\group, ~srcGrp,
							\out, bus,
							\pan, pan,
							\dur, Plprand(Pkey(\durRaw), Pkey(\durRaw) * 2, inf).round(1/16),
							\stretch, ~time,
							\buf, Pwrand([Pxrand(~percD[\crash]),
								Pxrand(~percD[\lows]),
								Pxrand(~percD[\mids]),
								Pxrand(~percD[\highs])], Pkey(\weights), inf),
							\rate, Pmeanrand(Pkey(\rateRaw) - 0.05, Pkey(\rateRaw) + 0.05, inf),
							\amp, Pexprand(0.3, 0.6, inf)
					)).play(quant: ~time),

					// Sine pdef [5]
					Pdef(stag,
						Pbind(
							\instrument, \sine,
							\group, ~srcGrp,
							\out, bus,
							\pan, pan,
							\dur, Plprand(Pkey(\durRaw), Pkey(\durRaw) * 4, inf).round(1/16),
							\stretch, ~time,
							\midinote, Pkey(\base),
							\harmonic, Pexprand(1, 12, inf).round,
							\amp, Pkey(\harmonic).reciprocal * 0.5,
							\atkRange, Pkey(\atkRaw) / 2,
							\relRange, Pkey(\relRaw) / 2,
							\atk, Pexprand(Pkey(\atkRaw) - Pkey(\atkRange),
								Pkey(\atkRaw) + Pkey(\atkRange), inf),
							\rel, Pexprand(Pkey(\relRaw) - Pkey(\relRange),
								Pkey(\relRaw) + Pkey(\relRange), inf),
					)).play(quant: ~time)
				));

				// Add a static text to the GUI for each tag
				{
					~viewD.add(tag ->
						StaticText()
						.background_(Color.white)
						.stringColor_(Color.black)
						.font_(Font.monospace(15));
					);

					// View gets added to Grid layout
					~gui_incoming_view.layout.add(~viewD[tag], ~vRow, ~vCol, \center);

					// Cycle through spots
					~vRow = ~vRow + 1;
					if (~vRow == ~vRowMax, {
						~vCol = (~vCol + 1) % ~vColMax;
						~vRow = ~vRow % ~vRowMax;
					});
				}.defer;
			});

			// Add delay to delay list
			~patD[tag][2][~patD[tag][0]] = timeDiff;
			// Calculate max delay
			diffMax = timeDiff;
			if (diffMax > ~patD[tag][1], {
				// If new diff is greater than old diff,
				// replace old diff
				~patD[tag][1] = diffMax;
			},
			{
				// Else set diffMax to max of avg and
				// linearly decreased diffMax
				var avg;
				avg = ~patD[tag][2].sum / ~diffArrayLen;
				~patD[tag][1] = max(~patD[tag][1] - ((~patD[tag][1] - avg) * 0.1), avg);
				diffMax = ~patD[tag][1];
			});
			// Set index
			~patD[tag][0] = (~patD[tag][0] + 1) % ~diffArrayLen;

			// Init sample weights
			weights = Array.with(0, 0, 0, 0);

			// How many bits to shave off,
			// depends on route hops
			precision = linlin(msg[4], 1, 15, 8, 1);

			// Reverb room size, depends on
			// distance in km to remote
			roomSize = linlin(msg[2], 0, 2000, 0, 0.8);

			// Pdef duration, depends on delay
			dur = linlin(timeDiff, 0, diffMax, 1/20, 1/2);

			// If it's daytime...
			if (msg[3] == 0, {
				dur = dur * 0.5;
				atkRaw = 0.2;
				relRaw = 1.5;
				base = 54;
				percRate = 1.2;
				weights[0] = linlin(timeDiff, 0, diffMax * 0.75, 0, 3);
			}, // Else...
			{
				atkRaw = 1.5;
				relRaw = 4;
				base = 47;
				percRate = 0.9;
				weights[0] = linlin(timeDiff, 0, diffMax * 0.75, 0, 15);
			});

			weights[1] = linlin(timeDiff, diffMax * 0.25, diffMax, 0, 7);
			weights[2] = gaussCurve(timeDiff, 10, diffMax / 2, 1.5);
			weights[3] = linlin(timeDiff, 0, diffMax * 0.75, 10, 0);

			weights = weights.normalizeSum;

			// Set reverb
			~patD[tag][3].set(\roomSize, roomSize);

			// Set rhythm and sine args
			~patD[tag][4].set(\durRaw, dur, \weights, weights, \precision, precision, \rateRaw, percRate).play;
			~patD[tag][5].set(\durRaw, dur, \base, base, \precision, precision, \atkRaw, atkRaw, \relRaw, relRaw).play;


			{
				~viewD[tag].string = "Remote: "++tag++"\nDelay: "++(timeDiff * 1000).round(0.01)++" ms ("++((timeDiff / diffMax) * 100).round(0.01)++"%)\nHops: "++msg[4]++"\nDistance: "++msg[2].round++" km\nNight time: "++if(msg[3] == 0, "No", "Yes");
			}.defer;

			//~viewD[tag].string = ~patD[tag][6].string++"tag-> "++tag++"\nDuration-> "++(dur * 16).round(0.1)++"/16\nPrecision-> "++(precision / 8 * 100).round(0.01)++"%\nRoom size-> "++roomSize.round(0.01)++"\nCrash-> "++(weights[0] * 100).round(0.1)++"%\nLow-> "++(weights[1] * 100).round(0.1)++"%\nMid-> "++(weights[2] * 100).round(0.1)++"%\nHigh-> "++(weights[3] * 100).round(0.1)++"%\n";


		},
		"/time"
	);
};

// ## STOP ##
~stopAll = {
	Pdef.removeAll;
	~revGrp.freeAll;
	~limGrp.freeAll;
}
)




