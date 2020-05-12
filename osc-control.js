/*
Max Mitchell
OSC Helper for SuperCollider project
Use with none, one, or two args
node osc-control.js [-r remote-ip] [-p remote-port] [-t tag] [-i message-send-interval] [-o test-offset]
Ip defaults to 0.0.0.0 (localhost)
Port defaults to 57120 (OSC default)
Tag defaults to large random number
Interval defaults to 500ms
Offset defaults to 0ms

Messages include:
    Time in raw seconds the message was sent
    Timezone offset in hours of the sender
    Is is night at the sender's location
    Router hops between sender and remote
*/

// OSC creates and listens for osc messages
const osc = require("osc");
// A better DateTime
const { DateTime } = require("luxon");
// Counts packet hops
const Traceroute = require("nodejs-traceroute");
// Parses args
const minimist = require("minimist");
// Used for GET requests
const axios = require("axios").default;
// Gets public facing IP
const publicIp = require("public-ip");

// Used to send OSC messages
const dgram = require('dgram');
// Socket for sending
const client = dgram.createSocket('udp4');

// Fetch args and set default values
let args = minimist(process.argv.slice(2), {
    default: {
        remote: "127.0.0.1",
        local: "127.0.0.1",
        port: 57120,
        testoffset: 0,
        interval: 500,
        tag: Math.floor(Math.random() * 2**24)
    },
    alias: {
        r: "remote",
        l: "local",
        p: "port",
        o: "testoffset",
        i: "interval",
        t: "tag"
    }
});

// The unique message ID
const TAG = args.tag;

// How often to send messages
const sendInterval = args.interval;

// If testing, max delay
const testingOffsetMax = args.testoffset;
// and random walk step size
const walkStep = testingOffsetMax / 2;

// Remote IP and port number
let remoteAddr = args.remote;
let remotePt = args.port;

// Local private IP
let localAddr = args.local;
// Local public IP
let localPublicAddr = "";

// Should the program send OSC data to remote
let doSend = false;

// If there is a Ctr-C, make sure to
// tell SuperCollider to stop playing,
// close the socket,
// and exit
process.on('SIGINT', () => {
    closeAndKill();
});

// Open a UDP socket to listen for OSC messages
const udpPort = new osc.UDPPort({
    localAddress: "127.0.0.1",
    localPort: 57121
});

// How many packet hops
let traceHops = 0;

// How far away is the remote
let distanceToRemote = 0;

// Sends OSC message
let sendOSC = function(msg) {
    client.send(msg, remotePt, remoteAddr, (err, bytes) => {
        if (err) console.log(err);
    });
}

// Sends OSC message to localhost
let sendLocal = function(msg) {
    client.send(msg, 57120, localAddr, (err, bytes) => {
        if (err) console.log(err);
    });
}

// Creates OSC message
let makeOscMessage = function(testOffset, distToRemote, numHops, tag, night=false) {
    const d = DateTime.local();

    // See if local time is at night
    let isNight = 0;
    if (d.hour <= 4 || d.hour >= 19 || night) {
        isNight = 1;
    }

    // Write message
    //  Current time
    //  Distance
    //  Night time
    //  Hops
    const msg = osc.writeMessage({
        address: "/time",
        args: [
            {
                type: "s",
                value: ((d.ts - testOffset) / 1000).toString()
            },
            {
                type: "f",
                value: distToRemote
            },
            {
                type: "i",
                value: isNight
            },
            {
                type: "i",
                value: numHops
            },
            {
                type: "s",
                value: tag
            }
        ]
    });
    
    return Buffer.from(msg);
}

// Create random walk, for testing
let randWalk = function(max, min, step, orand) {
    const range = Math.abs(max - min);
    if (orand < range * 0.2) {
        return Math.max((Math.random() - 0.2) * step, min);
    } else if (orand > range * 0.8) {
        return Math.min((Math.random() - 0.8) * step, max);
    } 
    return (Math.random() - 0.5) * step;
}

// Converts degrees to radians
let deg2rad = function(num) {
    return num * Math.PI / 180;
}

// Get distance in km between two geo-coordinates
let geoDistance = function(lat1, lon1, lat2, lon2) {
    const earthRadiusKm = 6371;
  
    const dLat = deg2rad(lat2-lat1);
    const dLon = deg2rad(lon2-lon1);
  
    lat1 = deg2rad(lat1);
    lat2 = deg2rad(lat2);
  
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.sin(dLon/2) * Math.sin(dLon/2) * Math.cos(lat1) * Math.cos(lat2); 
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
    return earthRadiusKm * c;
}

let makeSendMessage = function(send) {
    const msg = osc.writeMessage({
        address: "/isSending",
        args: [
            {
                type: "i",
                value: send
            }
        ]
    });
    return Buffer.from(msg);
}

let closeAndKill = function() {
    const msg = osc.writeMessage({
        address: "/stop",
        args: [
            {
                type: "s",
                value: TAG
            }
        ]
    });
    client.send(Buffer.from(msg), remotePt, remoteAddr, (err, bytes) => {
        if (err) console.log(err);
        client.close();
        process.exit();
    });
}

let makeCloseMessage = function(tag) {
    const msg = osc.writeMessage({
        address: "/stop",
        args: [
            {
                type: "s",
                value: tag
            }
        ]
    });
    return Buffer.from(msg);
}

let makeIPMessage = function() {
    const msg = osc.writeMessage({
        address: "/setPubIP",
        args: [
            {
                type: "s",
                value: localPublicAddr
            },
            {
                type: "s",
                value: remoteAddr
            }
        ]
    });
    return Buffer.from(msg);
}

// Listen for messages from SuperCollider
udpPort.on("message", function (oscMsg, timeTag, info) {
    if (oscMsg.address == "/getPubIP") {
        sendLocal(makeIPMessage());
    } else if (oscMsg.address == "/doSend") {
        if (oscMsg.args[0] == 1) {
            doSend = true;
            sendLocal(makeSendMessage(1));
        } else {
            doSend = false;
            sendOSC(makeCloseMessage(TAG));
            sendOSC(makeCloseMessage("Luke"));
            sendOSC(makeCloseMessage("Jim"));
            sendOSC(makeCloseMessage("Adam"));
            sendOSC(makeCloseMessage("Mark"));
            sendLocal(makeSendMessage(0));
        }
    }
});

// Open OSC port
udpPort.open();

// Some IP's for testing
const oh = "208.66.208.236";
const vt = "204.13.46.53";
const ca = "76.126.96.98";

// Remove for actual use
// remoteAddr = ca;

// Run traceroute to get hops,
// doesn't count hops that time out
try {
    const tracer = new Traceroute();
    tracer
        .on('destination', (destination) => {
            console.log(`Tracing hops to ${destination}`);
        })
        .on('hop', (hop) => {
            if (hop["rtt1"] != "*") traceHops += 1;
        })
        .on('close', (code) => {
            console.log(`Finished trace with ${traceHops} good hops out of 30.`);
        });

    tracer.trace(remoteAddr);
} catch(ex) {
    console.log(ex);
}

// Get local IP and geo-coordinates
try {
    (async () => {
        // Grab local IP
        localPublicAddr = await publicIp.v4();
        sendLocal(makeIPMessage());
        let localData;
        let remoteData;

        // Get local coordinates using IP
        axios.get(`https://ipvigilante.com/${localPublicAddr}`)
            .then(function (response) {
                localData = response.data.data;
                // Get remote coordinates
                axios.get(`https://ipvigilante.com/${remoteAddr}`)
                    .then(function (response) {
                        remoteData = response.data.data;

                        // Calculate distance
                        distanceToRemote = geoDistance(localData.latitude, localData.longitude, 
                            remoteData.latitude, remoteData.longitude);

                        console.log(`Remote is ${Math.round(distanceToRemote)} km away.`);
                    }).catch(function (error) {});
            }).catch(function (error) {});
    })();
} catch(err) {
    console.log(`Error, remote is now ${Math.round(distanceToRemote)} km away.`);
}

// Random delay for testing
let toffset = testingOffsetMax / 2;

// Send messages to remote
setInterval(function() {
    // Only send messages if told to
    if (doSend) {
        // If testing, calculate offset
        if (testingOffsetMax > 0) {
            toffset += randWalk(testingOffsetMax, 0, walkStep, toffset);
        }
        sendOSC(makeOscMessage(toffset, distanceToRemote, traceHops, TAG));
    }
}, sendInterval);

// Some other send loops for testing

/*
let to2 = testingOffsetMax / 2;

setInterval(function() {
    if (doSend) {
        if (testingOffsetMax > 0) {
            to2 += randWalk(testingOffsetMax, 0, walkStep, to2);
        }
        sendOSC(makeOscMessage(to2, 800, 15, "Luke", true));
    }
}, sendInterval * 2);

let to3 = testingOffsetMax / 2;

setInterval(function() {
    if (doSend) {
        if (testingOffsetMax > 0) {
            to3 += randWalk(testingOffsetMax * 0.5, 0, walkStep, to3);
        }
        sendOSC(makeOscMessage(to3, 50, 5, "Jim", true));
    }
}, sendInterval * 3);

let to4 = testingOffsetMax / 2;

setInterval(function() {
    if (doSend) {
        if (testingOffsetMax > 0) {
            to4 += randWalk(testingOffsetMax * 3, 0, walkStep, to4);
        }
        sendOSC(makeOscMessage(to2, 4000, 23, "Adam", true));
    }
}, sendInterval * 4);

let to5 = testingOffsetMax / 2;

setInterval(function() {
    if (doSend) {
        if (testingOffsetMax > 0) {
            to5 += randWalk(testingOffsetMax * 0.1, 0, walkStep, to5);
        }
        sendOSC(makeOscMessage(to3, 500, 7, "Mark", false));
    }
}, sendInterval * 4);

*/
