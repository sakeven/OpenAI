import Foundation

/// A local WebRTC media bridge; native Swift owns OAuth and all application operations.
enum CodexVoiceWebDocument {
    /// Bundled HTML only: no remote scripts, navigation, credential storage, or camera capture.
    static let html = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; media-src blob:">
    <style>html,body{margin:0;background:transparent}</style></head><body><script>
    let peer, channel, input, audio, context, oscillator, meter, inputMeter, outputMeter, disconnectTimer;
    let closed = false, reading = false, outputBegan = 0, lastSound = 0, finishAfter = null;
    let microphoneReady = false, microphoneMuted = true, previousAudioTime = 0;
    const post = value => { if (!closed) window.webkit.messageHandlers.voice.postMessage(value); };
    // Report media failures without exposing the SDP or the user's transcript to a log.
    const fail = error => post({failure: error.name === 'NotAllowedError' ? 'permission' : String(error.message || error)});
    window.voiceSend = event => {
        if (!channel || channel.readyState !== 'open') throw new Error('disconnected');
        const json = JSON.stringify(event);
        const limit = peer.sctp && peer.sctp.maxMessageSize;
        if (limit && new TextEncoder().encode(json).length > limit) throw new Error('textTooLong');
        channel.send(json);
    };
    // Stop both tracks and audio graphs, including the silent sender used by reading.
    window.voiceClose = () => {
        if (closed) return;
        try { if (window.voiceIsCodex) window.voiceSend({type:'session.close'}); } catch (_) {}
        closed = true;
        clearInterval(meter);
        clearTimeout(disconnectTimer);
        if (input) input.getTracks().forEach(track => track.stop());
        if (oscillator) oscillator.stop();
        if (audio) { audio.pause(); audio.srcObject = null; }
        if (channel) channel.close();
        if (peer) { peer.getReceivers().forEach(receiver => receiver.track.stop()); peer.close(); }
        if (context) context.close();
    };
    // The first call follows complete history replay; later calls retain the user's mute preference.
    window.voiceMute = muted => {
        microphoneReady = true; microphoneMuted = muted;
        if (input) input.getAudioTracks().forEach(track => track.enabled = !muted);
    };
    // Resume the current graph after a system interruption without silently unmuting the user.
    window.voiceResume = async () => {
        if (closed) return;
        if (context && context.state !== 'running') await context.resume();
        if (audio && audio.paused) await audio.play();
    };
    // The analyser reads actual input/output energy; silence stays still in the native waveform.
    const analyser = stream => {
        const node = context.createAnalyser(); node.fftSize = 256;
        context.createMediaStreamSource(stream).connect(node);
        return node;
    };
    const level = node => {
        if (!node) return 0;
        const samples = new Float32Array(node.fftSize); node.getFloatTimeDomainData(samples);
        return Math.sqrt(samples.reduce((sum, x) => sum + x*x, 0) / samples.length);
    };
    window.voiceStart = async microphone => {
        reading = !microphone;
        context = new AudioContext(); await context.resume();
        if (closed) return;
        if (microphone) {
            input = await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true},video:false});
            if (closed) { input.getTracks().forEach(track => track.stop()); return; }
            inputMeter = analyser(input);
            input.getAudioTracks().forEach(track => {
                track.enabled = false;
                track.onended = () => post({failure:'disconnected'});
            });
        } else {
            // Codex requires a running audio clock even for text-driven read-aloud calls.
            const destination = context.createMediaStreamDestination();
            const gain = context.createGain(); gain.gain.value = 0;
            oscillator = context.createOscillator(); oscillator.connect(gain).connect(destination);
            oscillator.start(); input = destination.stream;
        }
        peer = new RTCPeerConnection();
        input.getTracks().forEach(track => peer.addTrack(track, input));
        peer.onconnectionstatechange = () => {
            // Network handoffs may recover on this connection; only a persistent loss ends the call.
            if (peer.connectionState === 'disconnected') {
                if (!disconnectTimer) {
                    post({reconnecting:true});
                    disconnectTimer = setTimeout(() => {
                        disconnectTimer = null;
                        if (peer.connectionState === 'disconnected') post({failure:'disconnected'});
                    }, 10000);
                }
            } else if (peer.connectionState === 'connected') {
                clearTimeout(disconnectTimer); disconnectTimer = null;
                post({reconnecting:false});
            } else if (['failed','closed'].includes(peer.connectionState)) {
                clearTimeout(disconnectTimer); disconnectTimer = null;
                post({failure:'disconnected'});
            }
        };
        peer.ontrack = event => {
            const stream = event.streams[0] || new MediaStream([event.track]);
            audio = document.createElement('audio'); audio.autoplay = true; audio.srcObject = stream;
            document.body.appendChild(audio); audio.play().catch(fail);
            outputMeter = analyser(stream);
        };
        channel = peer.createDataChannel('oai-events');
        channel.onclose = () => post({failure:'disconnected'});
        channel.onerror = () => post({failure:'disconnected'});
        channel.onmessage = message => {
            try {
                const event = JSON.parse(message.data);
                if (reading && event.type === 'turn.done' && event.turn.role === 'assistant') {
                    // Wait for real playout and the declared utterance duration, not just inference completion.
                    const duration = Math.max(0, event.turn.end_ms - event.turn.start_ms);
                    finishAfter = Math.max(performance.now(), (outputBegan || performance.now()) + duration);
                }
                if (reading && event.type === 'output_audio_buffer.stopped') finishAfter = performance.now();
                post({event});
            } catch (error) { fail(error); }
        };
        meter = setInterval(() => {
            // Suspended graphs and muted input can retain old analyser samples; they are not live audio.
            const running = context.state === 'running';
            const tracks = input.getAudioTracks();
            const capturing = tracks.some(track => track.enabled && !track.muted && track.readyState === 'live');
            const incoming = running && capturing ? level(inputMeter) : 0;
            const outgoing = running && audio && !audio.paused ? level(outputMeter) : 0, now = performance.now();
            if (outgoing > 0.002) { if (!outputBegan) outputBegan = now; lastSound = now; }
            // An advancing audio clock proves readiness even in silence; volume is not a connection state.
            const mediaReady = (reading || microphoneReady) && running && context.currentTime > previousAudioTime
                && peer.connectionState === 'connected'
                && (reading || tracks.some(track => track.readyState === 'live' && (microphoneMuted || (track.enabled && !track.muted))));
            previousAudioTime = context.currentTime;
            post({inputLevel:incoming, outputLevel:outgoing, mediaReady});
            if (reading && finishAfter !== null && outputBegan && now >= finishAfter && now - lastSound > 800) {
                finishAfter = null; post({finished:true});
            }
        }, 100);
        const offer = await peer.createOffer(); await peer.setLocalDescription(offer);
        post({sdp:peer.localDescription.sdp});
    };
    window.voiceAnswer = async sdp => { if (!closed) await peer.setRemoteDescription({type:'answer',sdp}); };
    </script></body></html>
    """#
}
