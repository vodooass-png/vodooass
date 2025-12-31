#!/bin/bash
# --- ГЛАВНОЕ: Мгновенно падать при ошибках ---
set -e

# --- КОНФИГУРАЦИЯ ---
BOT_TOKEN="PUTYOURTOKENHERE"
LOCAL_PORT=8008
WEB_DIR="./website"
UPLOAD_DIR="./uploads"
TUNNEL_LOG="tunnel.log"
# --- КОНЕЦ КОНФИГУРАЦИИ ---

# --- Цвета ---
C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m';
C_PURPLE='\033[0;35m'; C_CYAN='\033[0;36m'; C_NC='\033[0m';
CHILD_PIDS=()

# --- Очистка ---
cleanup() {
    RETVAL=$?
    echo -e "\n${C_YELLOW}Завершение работы...${C_NC}"
    if [ ${#CHILD_PIDS[@]} -ne 0 ]; then
        kill -9 "${CHILD_PIDS[@]}" 2>/dev/null
    fi
    rm -f ${TUNNEL_LOG} requirements.txt
    rm -rf ${UPLOAD_DIR}
    if [ $RETVAL -ne 0 ]; then echo -e "${C_RED}Ошибка (Код: $RETVAL).${C_NC}"; else echo -e "${C_PURPLE}Выход.${C_NC}"; fi
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# --- Проверка ---
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${C_RED}Нет команды '$1'.${C_NC}"
        [[ "$1" == "python3" ]] && echo -e "${C_YELLOW}sudo pacman -S python${C_NC}"
        exit 1
    fi
}

# --- СТАРТ ---
clear
echo -e "${C_PURPLE}==============================================================${C_NC}"
echo -e "${C_PURPLE}==   Анонимный чат v21.0 (WA Audio Exact Look)              ==${C_NC}"
echo -e "${C_PURPLE}==============================================================${C_NC}"

check_command "python3"; check_command "pip"

# --- Зависимости ---
echo -e "\n${C_BLUE}[1/6] Настройка зависимостей...${C_NC}"
cat > requirements.txt << EOF
pycloudflared==0.2.0
python-telegram-bot==21.0.1
fastapi==0.111.0
uvicorn[standard]==0.29.0
websockets==12.0
python-multipart==0.0.9
aiofiles==23.2.1
EOF

VENV_DIR=".venv"
if [ ! -d "$VENV_DIR" ]; then python3 -m venv $VENV_DIR; fi
source $VENV_DIR/bin/activate
pip install -U -q pip setuptools wheel
pip install -q -r requirements.txt
echo -e "${C_GREEN}OK.${C_NC}"

# --- Интерфейс ---
echo -e "\n${C_BLUE}[2/6] Генерация интерфейса...${C_NC}"
mkdir -p ${WEB_DIR}
cat << 'EOF' > ${WEB_DIR}/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Chat</title>
    <style>
        :root { 
            --bg-color: #0e1621; --header-bg: #17212b; --input-bg: #17212b;
            --text-color: #f5f5f5; --text-meta: #6c7883; 
            --msg-in-bg: #182533; --msg-out-bg: #2b5278; 
            --green-accent: #2b5278; 
            --wa-teal: #00bfa5; /* WhatsApp Teal Color */
            --rec-color: #e91e63;
        }
        * { box-sizing: border-box; }
        body, html { margin: 0; padding: 0; height: 100%; font-family: -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif; background-color: var(--bg-color); color: var(--text-color); overflow: hidden; }
        .app-layout { display: flex; flex-direction: column; height: 100vh; }
        
        .header { padding: 10px 16px; background-color: var(--header-bg); border-bottom: 1px solid #000; display: flex; justify-content: space-between; align-items: center; z-index: 10; font-weight: bold; box-shadow: 0 1px 3px rgba(0,0,0,0.3); }
        .bg-btn { background: none; border: none; font-size: 1.5em; cursor: pointer; color: #fff; padding: 5px; }

        .messages { 
            flex-grow: 1; padding: 10px 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 8px;
            background-image: url("data:image/svg+xml,%3Csvg width='100' height='100' viewBox='0 0 100 100' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M10 10h10v10H10V10z' fill='%23121a24' fill-opacity='0.4'/%3E%3C/svg%3E"); 
            background-size: cover; background-position: center;
            scroll-behavior: smooth;
        }
        
        .msg-container { display: flex; width: 100%; }
        .msg-in { justify-content: flex-start; } .msg-in .msg-bubble { background-color: var(--msg-in-bg); border-bottom-left-radius: 0; }
        .msg-out { justify-content: flex-end; } .msg-out .msg-bubble { background-color: var(--msg-out-bg); border-bottom-right-radius: 0; }

        .msg-bubble { 
            padding: 6px 10px; border-radius: 12px; color: var(--text-color); 
            word-wrap: break-word; box-shadow: 0 1px 2px rgba(0,0,0,0.3); 
            max-width: 85%; min-width: 140px; position: relative;
        }

        .msg-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
        .msg-author { font-size: 0.85em; font-weight: bold; color: #64b5f6; }
        .call-icon { cursor: pointer; font-size: 1.1em; margin-left: 8px; text-decoration: none; opacity: 0.8; }
        .call-icon:hover { opacity: 1; transform: scale(1.1); }

        .msg-reply-context { border-left: 2px solid #64b5f6; padding-left: 8px; margin-bottom: 6px; font-size: 0.85em; color: rgba(255,255,255,0.7); background: rgba(0,0,0,0.1); border-radius: 4px; padding: 4px; }
        .msg-system-container { display: flex; justify-content: center; width: 100%; }
        .msg-system { background-color: rgba(0,0,0,0.3); color: var(--text-meta); font-size: 0.8em; padding: 4px 12px; border-radius: 12px; margin: 10px 0; }
        
        .chat-image { max-width: 100%; border-radius: 8px; margin-top: 5px; display: block; }
        .chat-video { max-width: 100%; border-radius: 8px; margin-top: 5px; display: block; background: #000; }
        
        /* --- WHATSAPP EXACT STYLE PLAYER --- */
        .audio-player { 
            display: flex; align-items: center; gap: 12px; 
            margin-top: 2px; margin-bottom: 2px;
            min-width: 240px; padding: 0; 
            background: transparent !important; /* Force transparent */
            border: none !important; /* No borders */
        }
        .play-btn { 
            width: 44px; height: 44px; 
            background-color: var(--wa-teal); 
            border-radius: 50%; border: none; 
            display: flex; justify-content: center; align-items: center; 
            cursor: pointer; color: #dcf8f6; font-size: 1.4em; 
            flex-shrink: 0; padding-left: 4px;
        }
        .play-btn svg { fill: white; width: 18px; height: 18px; }
        
        .audio-track { display: flex; flex-direction: column; flex-grow: 1; justify-content: center; height: 44px; }
        .waveform-canvas { width: 100%; height: 26px; opacity: 0.6; cursor: pointer; }
        
        .audio-meta { 
            display: flex; align-items: center; gap: 6px; 
            font-size: 0.7em; color: rgba(255,255,255,0.6); 
            margin-top: 3px;
            font-family: sans-serif;
        }
        .wa-dot { width: 4px; height: 4px; background-color: rgba(255,255,255,0.6); border-radius: 50%; }
        /* ---------------------------------- */

        .reply-bar { display: none; background: var(--header-bg); padding: 8px 16px; border-left: 4px solid var(--green-accent); align-items: center; justify-content: space-between; }
        .reply-info { display: flex; flex-direction: column; font-size: 0.9em; }
        .reply-author { color: var(--green-accent); font-weight: bold; }
        .reply-text { color: rgba(255,255,255,0.7); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 80vw; }
        
        .input-area { padding: 10px; background-color: var(--header-bg); display: flex; align-items: flex-end; gap: 10px; }
        #messageInput { flex-grow: 1; background-color: #0e1621; border: none; color: var(--text-color); padding: 12px 18px; border-radius: 20px; font-size: 1em; max-height: 100px; resize: none; }
        #messageInput:focus { outline: none; }
        .btn-icon { background: none; border: none; cursor: pointer; font-size: 1.8em; padding: 5px; color: #6c7883; transition: color 0.2s; line-height: 1; }
        .btn-icon:hover { color: #8295a5; }
        
        .recording-ui { display: none; flex-grow: 1; align-items: center; color: var(--rec-color); font-weight: bold; gap: 10px; padding: 12px; }
        .rec-dot { width: 10px; height: 10px; background-color: var(--rec-color); border-radius: 50%; animation: pulse 1s infinite; }
        @keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.5; } 100% { opacity: 1; } }
        
        .p2p-msg { background: #1c2a38; border: 1px solid var(--green-accent); padding: 10px; border-radius: 10px; margin-top: 5px; min-width: 250px; }
        .p2p-btn-action { background: var(--green-accent); color: white; border: none; padding: 8px 15px; border-radius: 5px; cursor: pointer; font-weight: bold; margin-top: 5px; width: 100%; }
        
        /* CALL OVERLAY */
        #call-overlay { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: #222b33; z-index: 2000; flex-direction: column; align-items: center; justify-content: center; }
        .call-avatar { width: 120px; height: 120px; border-radius: 50%; background: #444; margin-bottom: 20px; display: flex; justify-content: center; align-items: center; font-size: 3em; font-weight: bold; color: #fff; overflow: hidden; }
        .call-name { font-size: 1.5em; font-weight: bold; margin-bottom: 10px; }
        .call-status { font-size: 1em; color: #aaa; margin-bottom: 40px; }
        .call-controls { display: flex; gap: 30px; }
        .call-btn { width: 60px; height: 60px; border-radius: 50%; border: none; display: flex; justify-content: center; align-items: center; font-size: 1.5em; cursor: pointer; color: white; transition: 0.2s; }
        .btn-green { background: #4caf50; } .btn-red { background: #f44336; } .btn-grey { background: #555; }
        #remote-video { position: absolute; top: 0; left: 0; width: 100%; height: 100%; object-fit: cover; z-index: -1; display: none; }
        #local-video { position: absolute; bottom: 20px; right: 20px; width: 120px; height: 90px; object-fit: cover; border-radius: 10px; border: 2px solid #fff; z-index: 2001; display: none; }

        #nickname-modal { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); display: flex; justify-content: center; align-items: center; z-index: 1000; }
        #nickname-form { background: var(--header-bg); padding: 30px; border-radius: 10px; text-align: center; border: 1px solid #000; }
        #nickname-input { font-size: 1.2em; padding: 10px; margin-bottom: 20px; background: #0e1621; border: 1px solid #2b5278; color: white; }
    </style>
</head>
<body>
    <div id="nickname-modal">
        <div id="nickname-form">
            <h2>Никнейм</h2>
            <input type="text" id="nickname-input" autofocus>
            <br><button onclick="enterChat()" style="padding:10px 20px; background:#2b5278; color:white; border:none; border-radius:5px; cursor:pointer;">Войти</button>
        </div>
    </div>
    
    <div id="call-overlay">
        <video id="remote-video" autoplay playsinline></video>
        <video id="local-video" autoplay playsinline muted></video>
        <div class="call-avatar" id="call-avatar">A</div>
        <div class="call-name" id="call-name">User</div>
        <div class="call-status" id="call-status">Connecting...</div>
        <div class="call-controls" id="active-call-controls" style="display:none;">
            <button class="call-btn btn-grey" onclick="toggleVideo()">📷</button>
            <button class="call-btn btn-red" onclick="endCall()">✕</button>
            <button class="call-btn btn-grey" onclick="toggleAudio()">🎤</button>
        </div>
        <div class="call-controls" id="incoming-call-controls" style="display:none;">
            <button class="call-btn btn-green" onclick="answerCall()">📞</button>
            <button class="call-btn btn-red" onclick="endCall()">✕</button>
        </div>
    </div>

    <div class="app-layout">
        <div class="header">
            <span>Chat v21.0</span>
            <button class="bg-btn" id="bg-btn" title="Обои">🌗</button>
            <input type="file" id="bg-input" accept="image/*" style="display:none;">
        </div>
        
        <div id="messages-container" class="messages"></div>
        
        <div id="reply-bar" class="reply-bar">
            <div class="reply-info"><span class="reply-author" id="reply-author"></span><span class="reply-text" id="reply-text"></span></div>
            <div style="cursor:pointer; padding:5px;" onclick="cancelReply()">✕</div>
        </div>

        <form id="messageForm" class="input-area">
            <button type="button" id="p2p-btn" class="btn-icon" title="p2p передача больших файлов">⚡</button>
            <button type="button" id="file-btn" class="btn-icon" title="отправить media">⏏️</button>
            <input type="file" id="file-input" style="display:none;"/>
            <input type="file" id="p2p-input" style="display:none;"/>
            
            <input type="text" id="messageInput" placeholder="Сообщение..." autocomplete="off">
            <div id="recording-ui" class="recording-ui">
                <div class="rec-dot"></div><span id="rec-timer">00:00</span>
            </div>
            <button type="button" id="mic-btn" class="btn-icon" title="Записать">⏺️</button>
            <button type="submit" id="send-btn" class="btn-icon" style="color:#2b5278; display:none;">➤</button>
        </form>
    </div>

    <script>
        const D = id => document.getElementById(id);
        let ws, nickname, myClientId, replyTo = null;
        let mediaRecorder, audioChunks = [], recInterval;
        const activeLocalFiles = {}, peerConnections = {};
        let callPC = null, localStream = null, callTargetId = null;

        function uuidv4() { return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8); return v.toString(16); }); }

        function scrollToBottom() {
            const container = D('messages-container');
            container.scrollTop = container.scrollHeight;
        }

        function setupChat() {
            const savedBg = localStorage.getItem('chatWallpaper');
            if (savedBg) D('messages-container').style.backgroundImage = `url(${savedBg})`;
            nickname = sessionStorage.getItem('nickname');
            if (!nickname) D('nickname-modal').style.display = 'flex';
            else { D('nickname-modal').style.display = 'none'; connectWebSocket(); }
        }
        window.enterChat = () => {
            const nick = D('nickname-input').value.trim();
            if (nick) { nickname = nick; sessionStorage.setItem('nickname', nickname); D('nickname-modal').style.display = 'none'; connectWebSocket(); }
        };

        function connectWebSocket() {
            const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
            ws = new WebSocket(`${proto}//${window.location.host}/ws`);
            ws.onopen = () => ws.send(JSON.stringify({ type: 'join', nickname }));
            ws.onmessage = async event => { handleWsMessage(JSON.parse(event.data)); };
        }

        function handleWsMessage(data) {
            if (data.type === 'id') myClientId = data.id;
            else if (data.type === 'chat' || data.type === 'system') displayMessage(data);
            else if (data.type === 'p2p-offer') showP2POffer(data);
            else if (data.type === 'p2p-sync') data.offers.forEach(offer => showP2POffer(offer));
            else if (data.type === 'p2p-signal') handleP2PSignal(data);
            else if (data.type === 'call-signal') handleCallSignal(data);
        }

        // --- REAL WAVEFORM DRAW (WA STYLE) ---
        async function drawWaveform(url, canvasId) {
            const canvas = document.getElementById(canvasId);
            if(!canvas) return;
            const ctx = canvas.getContext('2d');
            
            try {
                const response = await fetch(url);
                const arrayBuffer = await response.arrayBuffer();
                const audioContext = new (window.AudioContext || window.webkitAudioContext)();
                const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
                
                const rawData = audioBuffer.getChannelData(0); 
                const samples = 48; // About 48 bars
                const blockSize = Math.floor(rawData.length / samples); 
                const width = canvas.width;
                const height = canvas.height;
                const gap = 3; // Gap between bars
                const barWidth = (width / samples) - gap;
                
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = '#b3b3b3'; // Grey bars (unplayed)
                
                for (let i = 0; i < samples; i++) {
                    let sum = 0;
                    for (let j = 0; j < blockSize; j++) {
                        sum += Math.abs(rawData[i * blockSize + j]);
                    }
                    const avg = sum / blockSize;
                    
                    // Scale bars
                    let barHeight = Math.max(2, avg * height * 4); 
                    if(barHeight > height) barHeight = height;

                    const x = i * (barWidth + gap);
                    const y = (height - barHeight) / 2;
                    
                    // Draw Rounded Rect manually
                    ctx.beginPath();
                    ctx.roundRect(x, y, barWidth, barHeight, 50); // Fully rounded
                    ctx.fill();
                }
            } catch (e) { console.error("Audio draw error", e); }
        }

        function displayMessage(data) {
            const msgDiv = document.createElement('div');
            if (data.type === 'system') {
                msgDiv.className = 'msg-system-container';
                msgDiv.innerHTML = `<div class='msg-system'>${data.text}</div>`;
            } else {
                const isMe = data.nickname === nickname;
                msgDiv.className = `msg-container ${isMe ? 'msg-out' : 'msg-in'}`;
                
                const bubble = document.createElement('div');
                bubble.className = 'msg-bubble';
                bubble.ondblclick = () => enableReply(bubble);

                if (data.reply) {
                    const rep = document.createElement('div');
                    rep.className = 'msg-reply-context';
                    rep.innerHTML = `<b>${data.reply.author}</b><br>${data.reply.text}`;
                    bubble.appendChild(rep);
                }
                
                if (!isMe) {
                    const header = document.createElement('div');
                    header.className = 'msg-header';
                    const auth = document.createElement('span');
                    auth.className = 'msg-author';
                    auth.textContent = data.nickname;
                    header.appendChild(auth);
                    
                    if (data.id) {
                        const callBtn = document.createElement('span');
                        callBtn.className = 'call-icon';
                        callBtn.textContent = '☎️'; 
                        callBtn.onclick = (e) => { e.stopPropagation(); startCall(data.id, data.nickname); };
                        header.appendChild(callBtn);
                    }
                    bubble.appendChild(header);
                }
                
                const content = document.createElement('div');
                content.className = 'msg-content';
                content.innerHTML = data.text;
                bubble.appendChild(content);
                msgDiv.appendChild(bubble);
            }
            D('messages-container').appendChild(msgDiv);
            scrollToBottom();
            
            // INITIALIZE AUDIO
            const canvas = msgDiv.querySelector('canvas');
            if (canvas) {
                const url = canvas.getAttribute('data-url');
                drawWaveform(url, canvas.id);
            }
            const media = msgDiv.querySelector('img, video');
            if(media) media.onload = media.onloadeddata = scrollToBottom;
        }

        // --- CALLS ---
        window.startCall = async (targetId, targetName) => {
            callTargetId = targetId; showCallOverlay(targetName, "Outgoing");
            try {
                localStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true });
                D('local-video').srcObject = localStream; D('local-video').style.display = 'block';
                callPC = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
                localStream.getTracks().forEach(t => callPC.addTrack(t, localStream));
                callPC.ontrack = e => { D('remote-video').srcObject = e.streams[0]; D('remote-video').style.display = 'block'; };
                callPC.onicecandidate = e => { if(e.candidate) ws.send(JSON.stringify({ type: 'call-signal', toId: targetId, signal: { candidate: e.candidate } })); };
                const offer = await callPC.createOffer(); await callPC.setLocalDescription(offer);
                ws.send(JSON.stringify({ type: 'call-signal', toId: targetId, signal: { sdp: callPC.localDescription } }));
            } catch (e) { alert("Error: " + e); endCall(); }
        };
        async function handleCallSignal(data) {
            const { fromId, fromNick, signal } = data;
            if (signal.hangup) { endCall(true); return; }
            if (!callPC) {
                callTargetId = fromId; showCallOverlay(fromNick, "Incoming");
                callPC = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
                callPC.ontrack = e => { D('remote-video').srcObject = e.streams[0]; D('remote-video').style.display = 'block'; };
                callPC.onicecandidate = e => { if(e.candidate) ws.send(JSON.stringify({ type: 'call-signal', toId: fromId, signal: { candidate: e.candidate } })); };
            }
            if (signal.sdp) { await callPC.setRemoteDescription(new RTCSessionDescription(signal.sdp)); }
            else if (signal.candidate) { await callPC.addIceCandidate(new RTCIceCandidate(signal.candidate)); }
        }
        window.answerCall = async () => {
            D('incoming-call-controls').style.display = 'none'; D('active-call-controls').style.display = 'flex'; D('call-status').textContent = "Connected";
            try {
                localStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true });
                D('local-video').srcObject = localStream; D('local-video').style.display = 'block';
                localStream.getTracks().forEach(t => callPC.addTrack(t, localStream));
                const answer = await callPC.createAnswer(); await callPC.setLocalDescription(answer);
                ws.send(JSON.stringify({ type: 'call-signal', toId: callTargetId, signal: { sdp: callPC.localDescription } }));
            } catch (e) { alert(e); endCall(); }
        };
        window.endCall = (remote = false) => {
            if (!remote && callTargetId) ws.send(JSON.stringify({ type: 'call-signal', toId: callTargetId, signal: { hangup: true } }));
            if (callPC) { callPC.close(); callPC = null; }
            if (localStream) { localStream.getTracks().forEach(t => t.stop()); localStream = null; }
            D('call-overlay').style.display = 'none'; D('remote-video').srcObject = null; callTargetId = null;
        };
        window.toggleVideo = () => { localStream.getVideoTracks()[0].enabled = !localStream.getVideoTracks()[0].enabled; };
        window.toggleAudio = () => { localStream.getAudioTracks()[0].enabled = !localStream.getAudioTracks()[0].enabled; };
        function showCallOverlay(name, type) {
            D('call-overlay').style.display = 'flex'; D('call-name').textContent = name; D('call-avatar').textContent = name.substring(0,2).toUpperCase();
            if (type === "Outgoing") { D('call-status').textContent = "Calling..."; D('active-call-controls').style.display = 'flex'; D('incoming-call-controls').style.display = 'none'; }
            else { D('call-status').textContent = "Incoming Call..."; D('active-call-controls').style.display = 'none'; D('incoming-call-controls').style.display = 'flex'; }
        }

        // --- GLOBALS ---
        D('bg-btn').onclick = () => D('bg-input').click();
        D('bg-input').onchange = () => { const f = D('bg-input').files[0]; if(f) { const r=new FileReader(); r.onload=e=>{ D('messages-container').style.backgroundImage=`url(${e.target.result})`; localStorage.setItem('chatWallpaper',e.target.result); }; r.readAsDataURL(f); } D('bg-input').value=''; };
        const msgInput = D('messageInput');
        msgInput.oninput = () => { if (msgInput.value.trim()) { D('mic-btn').style.display = 'none'; D('send-btn').style.display = 'block'; } else { D('mic-btn').style.display = 'block'; D('send-btn').style.display = 'none'; } };
        D('mic-btn').onclick = async () => {
            if (!mediaRecorder || mediaRecorder.state === "inactive") {
                try {
                    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
                    mediaRecorder = new MediaRecorder(stream); mediaRecorder.start();
                    msgInput.style.display = 'none'; D('recording-ui').style.display = 'flex'; audioChunks = []; let start = Date.now();
                    recInterval = setInterval(() => { const d = Math.floor((Date.now()-start)/1000); D('rec-timer').textContent = `${String(Math.floor(d/60)).padStart(2,'0')}:${String(d%60).padStart(2,'0')}`; }, 1000);
                    mediaRecorder.ondataavailable = e => audioChunks.push(e.data);
                    mediaRecorder.onstop = () => {
                        const file = new File([new Blob(audioChunks, { type: 'audio/webm' })], `voice_${Date.now()}.webm`, { type: 'audio/webm' });
                        const fd = new FormData(); fd.append('file', file); fd.append('nickname', nickname); fetch('/upload', { method: 'POST', body: fd });
                        stream.getTracks().forEach(t => t.stop()); clearInterval(recInterval); D('recording-ui').style.display = 'none'; msgInput.style.display = 'block'; D('rec-timer').textContent = "00:00";
                    };
                } catch { alert("No mic"); }
            } else mediaRecorder.stop();
        };
        function enableReply(elm) { replyTo = { text: elm.querySelector('.msg-content')?.textContent || "[Media]", author: elm.querySelector('.msg-author')?.textContent || "Я" }; D('reply-author').textContent = replyTo.author; D('reply-text').textContent = replyTo.text; D('reply-bar').style.display = 'flex'; msgInput.focus(); }
        window.cancelReply = () => { replyTo = null; D('reply-bar').style.display = 'none'; }
        
        // --- AUDIO CONTROLS ---
        window.toggleAudio = function(btn) {
            const audio = btn.parentElement.parentElement.querySelector('audio');
            document.querySelectorAll('audio').forEach(a => { if(a!==audio && !a.paused) { a.pause(); a.currentTime=0; a.parentElement.querySelector('.play-btn').innerHTML='▶'; }});
            if(audio.paused) { audio.play(); btn.innerHTML='⏸'; } else { audio.pause(); btn.innerHTML='▶'; }
        };
        window.resetAudio = function(audio) { audio.parentElement.querySelector('.play-btn').innerHTML='▶'; };
        // -----------------------

        D('messageForm').onsubmit = e => { e.preventDefault(); if (msgInput.value.trim()) { ws.send(JSON.stringify({ type: 'chat', text: msgInput.value.trim(), reply: replyTo })); msgInput.value = ''; msgInput.oninput(); cancelReply(); } };
        D('file-btn').onclick = () => D('file-input').click();
        D('file-input').onchange = async () => { if(D('file-input').files[0]) { const fd = new FormData(); fd.append('file', D('file-input').files[0]); fd.append('nickname', nickname); await fetch('/upload', { method: 'POST', body: fd }); D('file-input').value = ''; } };
        D('p2p-btn').onclick = () => D('p2p-input').click();
        D('p2p-input').onchange = () => { const f=D('p2p-input').files[0]; if(!f) return; const fid=uuidv4(); activeLocalFiles[fid]=f; ws.send(JSON.stringify({ type: 'p2p-announce', fileId: fid, filename: f.name, size: f.size })); showP2POffer({fromId:myClientId, nickname:'Вы', filename:f.name, size:f.size, fileId:fid}); D('p2p-input').value=''; };
        function showP2POffer(d) { if(D(`offer-${d.fileId}`)) return; const t=`<div class="p2p-msg" id="offer-${d.fileId}"><div>⚡ <b>${d.nickname}</b>: ${d.filename} (${(d.size/1024/1024).toFixed(2)} MB)</div><div class="p2p-status" id="status-${d.fileId}"></div>${d.fromId !== myClientId ? `<button class="p2p-btn-action" onclick="initP2P('${d.fromId}','${d.fileId}','${d.filename}')">⬇️ СКАЧАТЬ</button>` : ''}</div>`; const m=document.createElement('div'); m.className='msg-container msg-in'; m.innerHTML=`<div class="msg-bubble" style="padding:0;background:transparent;box-shadow:none;">${t}</div>`; D('messages-container').appendChild(m); scrollToBottom(); }
        window.initP2P = async (tid, fid, n) => { const sid=uuidv4(); const b=document.querySelector(`#offer-${fid} button`); const s=document.querySelector(`#status-${fid}`); b.disabled=true; b.textContent="..."; const pc=new RTCPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]}); peerConnections[sid]=pc; pc.ondatachannel=e=>setupRx(e.channel,n,b,s,sid); pc.onicecandidate=e=>{if(e.candidate)ws.send(JSON.stringify({type:'p2p-signal',toId:tid,sessionId:sid,fileId:fid,signal:{candidate:e.candidate}}))}; pc.createDataChannel("signaling"); const o=await pc.createOffer(); await pc.setLocalDescription(o); ws.send(JSON.stringify({type:'p2p-signal',toId:tid,sessionId:sid,fileId:fid,signal:{sdp:pc.localDescription}})); };
        async function handleP2PSignal(d) { const {fromId,sessionId,fileId,signal}=d; if(!peerConnections[sessionId]){ const f=activeLocalFiles[fileId]; if(!f) return; const pc=new RTCPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]}); peerConnections[sessionId]=pc; pc.onicecandidate=e=>{if(e.candidate)ws.send(JSON.stringify({type:'p2p-signal',toId:fromId,sessionId,fileId,signal:{candidate:e.candidate}}))}; const dc=pc.createDataChannel("fileTransfer"); setupTx(dc,f); } const pc=peerConnections[sessionId]; if(signal.sdp){ await pc.setRemoteDescription(new RTCSessionDescription(signal.sdp)); if(signal.sdp.type==='offer'){ const a=await pc.createAnswer(); await pc.setLocalDescription(a); ws.send(JSON.stringify({type:'p2p-signal',toId:fromId,sessionId,fileId,signal:{sdp:pc.localDescription}})); } } else if(signal.candidate) await pc.addIceCandidate(new RTCIceCandidate(signal.candidate)); }
        function setupTx(dc,f) { dc.onopen=()=>{ const r=new FileReader(); let o=0; r.onload=e=>{ if(dc.readyState!=='open')return; dc.send(e.target.result); o+=e.target.result.byteLength; if(o<f.size){ if(dc.bufferedAmount>16000000) setTimeout(()=>r.readAsArrayBuffer(f.slice(o,o+16384)),100); else r.readAsArrayBuffer(f.slice(o,o+16384)); } else dc.close(); }; r.readAsArrayBuffer(f.slice(o,o+16384)); }; }
        function setupRx(dc,n,b,s,sid) { const c=[]; let r=0; dc.onopen=()=>{s.textContent="DL..."}; dc.onmessage=e=>{c.push(e.data); r+=e.data.byteLength; s.textContent=`${(r/1024/1024).toFixed(2)} MB`}; dc.onclose=()=>{ const a=document.createElement('a'); a.href=URL.createObjectURL(new Blob(c)); a.download=n; a.click(); s.textContent="OK"; b.disabled=false; b.textContent="Save"; peerConnections[sid].close(); delete peerConnections[sid]; }; }
        setupChat();
    </script>
</body>
</html>
EOF
echo -e "${C_GREEN}OK.${C_NC}"

# --- Бэкенд ---
echo -e "\n${C_BLUE}[3/6] Настройка сервера...${C_NC}"
cat << EOF > web_app.py
import asyncio, json, uuid
from pathlib import Path
import aiofiles
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, UploadFile, File, Form
from fastapi.responses import HTMLResponse, JSONResponse, FileResponse

ACTIVE_OFFERS = {}
class ConnMgr:
    def __init__(self): self.conns = {}; self.nicks = {}
    async def connect(self, ws): await ws.accept(); cid=str(uuid.uuid4()); self.conns[cid]=ws; await ws.send_text(json.dumps({"type":"id","id":cid})); return cid
    async def disconnect(self, cid):
        if cid in self.conns:
            del self.conns[cid]; nick=self.nicks.pop(cid,'Anon')
            if cid in ACTIVE_OFFERS: del ACTIVE_OFFERS[cid]
            await self.broadcast({"type":"system","text":f"{nick} вышел."})
    async def broadcast(self, data):
        msg = json.dumps(data)
        await asyncio.gather(*[ws.send_text(msg) for ws in self.conns.values()])
    async def handle(self, cid, data):
        t = data.get("type"); nick = self.nicks.get(cid, "Anon")
        if t == 'join':
            self.nicks[cid] = data.get('nickname','Anon')
            await self.broadcast({"type":"system","text":f"{self.nicks[cid]} вошел."})
            offers = [o for u in ACTIVE_OFFERS.values() for o in u.values()]
            if offers: await self.conns[cid].send_text(json.dumps({"type":"p2p-sync","offers":offers}))
        elif t == 'chat': 
            await self.broadcast({"type":"chat","id":cid,"nickname":nick,"text":data.get("text"),"reply":data.get("reply")})
        elif t == 'p2p-announce':
            fid = data.get('fileId'); data['fromId']=cid; data['nickname']=nick; data['type']='p2p-offer'
            if cid not in ACTIVE_OFFERS: ACTIVE_OFFERS[cid]={}
            ACTIVE_OFFERS[cid][fid] = data
            await self.broadcast(data)
        elif t == 'p2p-signal':
            tgt = data.get('toId')
            if tgt in self.conns:
                payload = {"type":"p2p-signal","fromId":cid,"sessionId":data.get("sessionId"),"fileId":data.get("fileId"),"signal":data.get("signal")}
                await self.conns[tgt].send_text(json.dumps(payload))
        elif t == 'call-signal':
            tgt = data.get('toId')
            if tgt in self.conns:
                payload = {"type":"call-signal","fromId":cid,"fromNick":nick,"signal":data.get("signal")}
                await self.conns[tgt].send_text(json.dumps(payload))

app = FastAPI(); mgr = ConnMgr()
UPLOAD_DIR = Path("${UPLOAD_DIR}"); UPLOAD_DIR.mkdir(exist_ok=True); FILE_DB = {}

@app.get("/")
async def get(): return HTMLResponse(Path("./website/index.html").read_text())

@app.post("/upload")
async def upload(nickname: str = Form(...), file: UploadFile = File(...)):
    fid = str(uuid.uuid4()); fpath = UPLOAD_DIR / f"{fid}_{file.filename}"
    content = await file.read()
    async with aiofiles.open(fpath, 'wb') as f: await f.write(content)
    FILE_DB[fid] = fpath; url = f"/download/{fid}/{file.filename}"
    ext = file.filename.split('.')[-1].lower()
    
    # Calc size for UI
    size_mb = len(content) / 1024 / 1024
    size_str = f"{size_mb:.1f} MB" if size_mb >= 1 else f"{len(content)/1024:.0f} KB"
    
    if ext in ['jpg','png','jpeg','gif','webp']: text = f"<img src='{url}' class='chat-image' onclick='window.open(this.src)'>"
    elif ext in ['mp4','mov','mkv']: text = f"<video src='{url}' controls class='chat-video'></video>"
    elif ext in ['mp3','wav','ogg', 'webm']: 
        # --- NO FRAME. PURE WA STYLE PLAYER HTML ---
        text = (f"<div class='audio-player'>"
                f"<button class='play-btn' onclick='toggleAudio(this)'>▶</button>"
                f"<div class='audio-track'>"
                f"<canvas id='wave-{fid}' class='waveform-canvas' width='220' height='26' data-url='{url}'></canvas>"
                f"<div class='audio-meta'>"
                f"<span>{size_str}</span><span class='wa-dot'></span><span>Audio</span>"
                f"</div></div>"
                f"<audio src='{url}' onended='resetAudio(this)'></audio></div>")
    else: text = f"📄 <b>{file.filename}</b> <a href='{url}' style='color:#64b5f6'>[Скачать]</a>"
    
    await mgr.broadcast({"type":"chat","id":"server","nickname":nickname,"text":text})
    return {"status":"ok"}

@app.get("/download/{fid}/{name}")
async def download(fid: str, name: str): return FileResponse(FILE_DB.get(fid), filename=name)

@app.websocket("/ws")
async def ws(ws: WebSocket):
    cid = await mgr.connect(ws)
    try:
        while True: await mgr.handle(cid, json.loads(await ws.receive_text()))
    except: await mgr.disconnect(cid)
EOF
echo -e "${C_GREEN}OK.${C_NC}"

# --- Бот ---
echo -e "\n${C_BLUE}[4/6] Настройка бота...${C_NC}"
cat << EOF > bot.py
import sys
from telegram import Update
from telegram.ext import Application, CommandHandler
async def start(u, c): await u.message.reply_html(f"🔗 <b>{sys.argv[1] if len(sys.argv)>1 else 'Error'}</b>")
def main():
    app = Application.builder().token("${BOT_TOKEN}").build()
    app.add_handler(CommandHandler("start", start))
    app.run_polling()
if __name__ == "__main__": main()
EOF
echo -e "${C_GREEN}OK.${C_NC}"

# --- Запуск ---
echo -e "\n${C_BLUE}[5/6] Запуск сервисов...${C_NC}"
uvicorn web_app:app --host 0.0.0.0 --port ${LOCAL_PORT} --log-level warning &
SERVER_PID=$!; CHILD_PIDS+=($SERVER_PID)

cloudflared tunnel --url http://localhost:${LOCAL_PORT} --no-autoupdate > ${TUNNEL_LOG} 2>&1 &
TUNNEL_PID=$!; CHILD_PIDS+=($TUNNEL_PID)

echo -n "Ожидание ссылки..."
for i in {1..30}; do
    PUBLIC_URL=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare.com' ${TUNNEL_LOG} || true)
    if [ -n "$PUBLIC_URL" ]; then break; fi
    sleep 1; echo -n "."
done
echo ""

if [ -z "$PUBLIC_URL" ]; then echo -e "${C_RED}Не удалось получить ссылку Cloudflare.${C_NC}"; exit 1; fi

python3 bot.py "$PUBLIC_URL" &
BOT_PID=$!; CHILD_PIDS+=($BOT_PID)

echo -e "\n${C_GREEN}====================== СИСТЕМА АКТИВНА ======================${C_NC}"
echo -e "Ссылка: ${C_CYAN}${PUBLIC_URL}${C_NC}"
echo -e "${C_YELLOW}Нажмите CTRL+C для выхода.${C_NC}"

wait ${SERVER_PID}
echo -e "${C_RED}Сервер остановлен.${C_NC}"