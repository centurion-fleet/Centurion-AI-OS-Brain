#!/usr/bin/env node
/**
 * Centurion AI OS WhatsApp Bridge
 *
 * Standalone Node.js process that connects to WhatsApp via Baileys
 * and exposes HTTP endpoints for the Python gateway adapter.
 *
 * Endpoints (matches gateway/platforms/whatsapp.py expectations):
 *   GET  /messages       - Long-poll for new incoming messages
 *   POST /send           - Send a message { chatId, message, replyTo? }
 *   POST /edit           - Edit a sent message { chatId, messageId, message }
 *   POST /send-media     - Send media natively { chatId, filePath, mediaType?, caption?, fileName? }
 *   POST /typing         - Send typing indicator { chatId }
 *   GET  /chat/:id       - Get chat info
 *   GET  /health         - Health check
 *
 * Usage:
 *   node bridge.js --port 3000 --session ~/.centurion/whatsapp/session
 */

import { makeWASocket, useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion, downloadMediaMessage } from '@whiskeysockets/baileys';
import express from 'express';
import { Boom } from '@hapi/boom';
import pino from 'pino';
import path from 'path';
import { mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, unlinkSync } from 'fs';
import { randomBytes } from 'crypto';
import { execSync } from 'child_process';
import { tmpdir } from 'os';
import qrcode from 'qrcode-terminal';
import { matchesAllowedUser, parseAllowedUsers } from './allowlist.js';

// Parse CLI args
const args = process.argv.slice(2);
function getArg(name, defaultVal) {
  const idx = args.indexOf(`--${name}`);
  return idx !== -1 && args[idx + 1] ? args[idx + 1] : defaultVal;
}

const WHATSAPP_DEBUG =
  typeof process !== 'undefined' &&
  process.env &&
  typeof process.env.WHATSAPP_DEBUG === 'string' &&
  ['1', 'true', 'yes', 'on'].includes(process.env.WHATSAPP_DEBUG.toLowerCase());

const PORT = parseInt(getArg('port', '3000'), 10);
const SESSION_DIR = getArg('session', path.join(process.env.HOME || '~', '.centurion', 'whatsapp', 'session'));
const IMAGE_CACHE_DIR = path.join(process.env.HOME || '~', '.centurion', 'image_cache');
const DOCUMENT_CACHE_DIR = path.join(process.env.HOME || '~', '.centurion', 'document_cache');
const AUDIO_CACHE_DIR = path.join(process.env.HOME || '~', '.centurion', 'audio_cache');
const PAIR_ONLY = args.includes('--pair-only');
const WHATSAPP_MODE = getArg('mode', process.env.WHATSAPP_MODE || 'self-chat'); // "bot" or "self-chat"
const ALLOWED_USERS = parseAllowedUsers(process.env.WHATSAPP_ALLOWED_USERS || '');
const DEFAULT_REPLY_PREFIX = '⚕ *Centurion AI OS*\n────────────\n';
const REPLY_PREFIX = process.env.WHATSAPP_REPLY_PREFIX === undefined
  ? DEFAULT_REPLY_PREFIX
  : process.env.WHATSAPP_REPLY_PREFIX.replace(/\\n/g, '\n');
const MAX_MESSAGE_LENGTH = parseInt(process.env.WHATSAPP_MAX_MESSAGE_LENGTH || '4096', 10);
const CHUNK_DELAY_MS = parseInt(process.env.WHATSAPP_CHUNK_DELAY_MS || '300', 10);
// Per-call timeout for sock.sendMessage(). Baileys occasionally hangs forever
// when uploading media to WhatsApp servers (and, less often, on text sends),
// which pins the bridge's HTTP handler until the upstream aiohttp timeout
// fires. Fail fast instead so the gateway can surface a real error and retry.
const SEND_TIMEOUT_MS = parseInt(process.env.WHATSAPP_SEND_TIMEOUT_MS || '60000', 10);

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function sendWithTimeout(chatId, payload, timeoutMs = SEND_TIMEOUT_MS) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`sendMessage timed out after ${timeoutMs / 1000}s`)),
      timeoutMs,
    );
  });
  return Promise.race([sock.sendMessage(chatId, payload), timeoutPromise])
    .finally(() => clearTimeout(timer));
}

function formatOutgoingMessage(message) {
  // In bot mode, messages come from a different number so the prefix is
  // redundant — the sender identity is already clear.  Only prepend in
  // self-chat mode where bot and user share the same number.
  if (WHATSAPP_MODE !== 'self-chat') return message;
  return REPLY_PREFIX ? `${REPLY_PREFIX}${message}` : message;
}

function splitLongMessage(message, maxLength = MAX_MESSAGE_LENGTH) {
  const text = String(message || '');
  if (!text) return [];
  if (!Number.isFinite(maxLength) || maxLength < 1 || text.length <= maxLength) {
    return [text];
  }

  const chunks = [];
  let remaining = text;
  while (remaining.length > maxLength) {
    let splitAt = remaining.lastIndexOf('\n', maxLength);
    if (splitAt < Math.floor(maxLength / 2)) {
      splitAt = remaining.lastIndexOf(' ', maxLength);
    }
    if (splitAt < 1) splitAt = maxLength;

    chunks.push(remaining.slice(0, splitAt).trimEnd());
    remaining = remaining.slice(splitAt).trimStart();
  }
  if (remaining) chunks.push(remaining);
  return chunks;
}

function trackSentMessageId(sent) {
  if (sent?.key?.id) {
    recentlySentIds.add(sent.key.id);
    if (recentlySentIds.size > MAX_RECENT_IDS) {
      recentlySentIds.delete(recentlySentIds.values().next().value);
    }
  }
}

function normalizeWhatsAppId(value) {
  if (!value) return '';
  return String(value).replace(':', '@');
}

function getMessageContent(msg) {
  const content = msg?.message || {};
  if (content.ephemeralMessage?.message) return content.ephemeralMessage.message;
  if (content.viewOnceMessage?.message) return content.viewOnceMessage.message;
  if (content.viewOnceMessageV2?.message) return content.viewOnceMessageV2.message;
  if (content.documentWithCaptionMessage?.message) return content.documentWithCaptionMessage.message;
  if (content.templateMessage?.hydratedTemplate) return content.templateMessage.hydratedTemplate;
  if (content.buttonsMessage) return content.buttonsMessage;
  if (content.listMessage) return content.listMessage;
  return content;
}

function getContextInfo(messageContent) {
  if (!messageContent || typeof messageContent !== 'object') return {};
  for (const value of Object.values(messageContent)) {
    if (value && typeof value === 'object' && value.contextInfo) {
      return value.contextInfo;
    }
  }
  return {};
}

mkdirSync(SESSION_DIR, { recursive: true });

// Build LID → phone reverse map from session files (lid-mapping-{phone}.json)
function buildLidMap() {
  const map = {};
  try {
    for (const f of readdirSync(SESSION_DIR)) {
      const m = f.match(/^lid-mapping-(\d+)\.json$/);
      if (!m) continue;
      const phone = m[1];
      const lid = JSON.parse(readFileSync(path.join(SESSION_DIR, f), 'utf8'));
      if (lid) map[String(lid)] = phone;
    }
  } catch {}
  return map;
}
let lidToPhone = buildLidMap();

const logger = pino({ level: 'warn' });

// Message queue for polling
const messageQueue = [];
const MAX_QUEUE_SIZE = 100;

// Track recently sent message IDs to prevent echo-back loops with media
const recentlySentIds = new Set();
const MAX_RECENT_IDS = 50;

let sock = null;
let connectionState = 'disconnected'; // disconnected | connecting | connected | reconnecting
let reconnectAttempts = 0;
let reconnectTimer = null;
let startingSocket = false;
let socketGeneration = 0;

const RECONNECT_BASE_MS = parseInt(process.env.WHATSAPP_RECONNECT_BASE_MS || '2000', 10);
const RECONNECT_MAX_MS = parseInt(process.env.WHATSAPP_RECONNECT_MAX_MS || '60000', 10);
const RECONNECT_MAX_ATTEMPTS = parseInt(process.env.WHATSAPP_RECONNECT_MAX_ATTEMPTS || '0', 10); // 0 = unlimited

/** Human-readable labels for Baileys / WhatsApp stream close codes. */
const DISCONNECT_REASON_LABELS = {
  [DisconnectReason.loggedOut]: 'loggedOut',
  [DisconnectReason.connectionClosed]: 'connectionClosed',
  [DisconnectReason.connectionLost]: 'connectionLost',
  [DisconnectReason.connectionReplaced]: 'connectionReplaced',
  [DisconnectReason.timedOut]: 'timedOut',
  [DisconnectReason.badSession]: 'badSession',
  [DisconnectReason.restartRequired]: 'restartRequired',
  [DisconnectReason.multideviceMismatch]: 'multideviceMismatch',
  [DisconnectReason.forbidden]: 'forbidden',
  [DisconnectReason.unavailableService]: 'unavailableService',
};

function disconnectReasonLabel(code) {
  if (code == null) return 'unknown';
  // Baileys maps both connectionLost and timedOut to 408.
  if (code === 408) return 'connectionLost/timedOut';
  if (code === DisconnectReason.connectionClosed) return 'connectionClosed';
  return DISCONNECT_REASON_LABELS[code] || `code_${code}`;
}

function clearReconnectTimer() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

function scheduleReconnect(reasonCode, detail = '') {
  clearReconnectTimer();

  if (PAIR_ONLY) {
    console.error('❌ Pairing connection closed before success. Re-run pairing.');
    process.exit(1);
  }

  if (
    RECONNECT_MAX_ATTEMPTS > 0 &&
    reconnectAttempts >= RECONNECT_MAX_ATTEMPTS
  ) {
    console.error(
      `❌ Gave up after ${reconnectAttempts} reconnect attempts. ` +
        `Last reason=${disconnectReasonLabel(reasonCode)} (${reasonCode}). ` +
        'Restart the bridge (or clear the session if logged out).',
    );
    process.exit(1);
  }

  reconnectAttempts += 1;
  connectionState = 'reconnecting';

  // Fast path after pairing restart; otherwise exponential backoff + jitter.
  let delayMs;
  if (reasonCode === DisconnectReason.restartRequired) {
    delayMs = 1000;
  } else if (reasonCode === DisconnectReason.connectionReplaced) {
    // Another WhatsApp Web / linked device took the socket — wait longer
    // so we don't fight the other client in a tight loop.
    delayMs = Math.min(RECONNECT_MAX_MS, 15000);
  } else {
    const exp = Math.min(
      RECONNECT_MAX_MS,
      RECONNECT_BASE_MS * (2 ** Math.min(reconnectAttempts - 1, 5)),
    );
    const jitter = Math.floor(Math.random() * Math.min(1000, exp * 0.2));
    delayMs = exp + jitter;
  }

  const label = disconnectReasonLabel(reasonCode);
  console.warn(
    JSON.stringify({
      event: 'connection_closed',
      reason: label,
      reasonCode: reasonCode ?? null,
      detail: detail || undefined,
      attempt: reconnectAttempts,
      reconnectInMs: delayMs,
    }),
  );
  console.log(
    `⚠️  WhatsApp disconnected (${label}` +
      `${reasonCode != null ? ` / ${reasonCode}` : ''}` +
      `${detail ? `: ${detail}` : ''}). ` +
      `Reconnecting in ${(delayMs / 1000).toFixed(1)}s ` +
      `(attempt ${reconnectAttempts}` +
      `${RECONNECT_MAX_ATTEMPTS > 0 ? `/${RECONNECT_MAX_ATTEMPTS}` : ''})...`,
  );

  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    startSocket().catch((err) => {
      console.error('❌ Reconnect start failed:', err?.message || err);
      scheduleReconnect(DisconnectReason.connectionLost, String(err?.message || err));
    });
  }, delayMs);
}

async function startSocket() {
  if (startingSocket) {
    console.log('⏳ Socket start already in progress — skipping duplicate call.');
    return;
  }
  startingSocket = true;
  clearReconnectTimer();
  connectionState = 'connecting';
  const generation = ++socketGeneration;

  const releaseStartLock = () => {
    if (generation === socketGeneration) {
      startingSocket = false;
    }
  };

  try {
    // Drop the previous socket listeners so a late 'close' from an old
    // connection cannot schedule a second reconnect race.
    if (sock) {
      try {
        sock.ev.removeAllListeners('connection.update');
        sock.ev.removeAllListeners('creds.update');
        sock.ev.removeAllListeners('messages.upsert');
        sock.end?.(undefined);
      } catch {}
      sock = null;
    }

    const { state, saveCreds } = await useMultiFileAuthState(SESSION_DIR);
    const { version } = await fetchLatestBaileysVersion();

    sock = makeWASocket({
      version,
      auth: state,
      logger,
      printQRInTerminal: false,
      browser: ['Centurion AI OS', 'Chrome', '120.0'],
      syncFullHistory: false,
      // Defense-in-depth for history-sync spoofing (GHSA-qvv5-jq5g-4cgg).
      shouldSyncHistoryMessage: () => false,
      markOnlineOnConnect: false,
      connectTimeoutMs: 60_000,
      keepAliveIntervalMs: 25_000,
      retryRequestDelayMs: 500,
      // Without this, incoming messages that need E2EE session re-establishment
      // can arrive with msg.message === null.
      getMessage: async () => ({ conversation: '' }),
    });

    sock.ev.on('creds.update', () => { saveCreds(); lidToPhone = buildLidMap(); });

    sock.ev.on('connection.update', (update) => {
      if (generation !== socketGeneration) return;

      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        console.log('\n📱 Scan this QR code with WhatsApp on your phone:\n');
        qrcode.generate(qr, { small: true });
        console.log('\nWaiting for scan...\n');
      }

      if (connection === 'connecting') {
        connectionState = 'connecting';
        return;
      }

      if (connection === 'close') {
        const boom = new Boom(lastDisconnect?.error);
        const reason = boom?.output?.statusCode;
        const errMsg =
          lastDisconnect?.error?.message ||
          boom?.message ||
          '';
        connectionState = 'disconnected';
        releaseStartLock();

        // Fatal: user logged out from the phone — needs a fresh QR pair.
        if (reason === DisconnectReason.loggedOut) {
          console.error(
            '❌ Logged out (DisconnectReason.loggedOut / 401). ' +
              `Delete session dir and re-pair: ${SESSION_DIR}`,
          );
          process.exit(1);
        }

        // Fatal-ish: session files are corrupt / incompatible.
        if (reason === DisconnectReason.badSession) {
          console.error(
            '❌ Bad session (DisconnectReason.badSession). ' +
              `Delete ${SESSION_DIR} and re-pair with --pair-only.`,
          );
          process.exit(1);
        }

        if (reason === DisconnectReason.multideviceMismatch) {
          console.error(
            '❌ Multi-device mismatch. Re-pair this bridge as a linked device.',
          );
          process.exit(1);
        }

        // 408 connectionLost/timedOut and 428 connectionClosed are normal
        // WhatsApp stream drops — reconnect with backoff.
        scheduleReconnect(reason, errMsg);
      } else if (connection === 'open') {
        reconnectAttempts = 0;
        connectionState = 'connected';
        releaseStartLock();
        console.log('✅ WhatsApp connected!');
        if (PAIR_ONLY) {
          console.log('✅ Pairing complete. Credentials saved.');
          // Give Baileys a moment to flush creds, then exit cleanly
          setTimeout(() => process.exit(0), 2000);
        }
      }
    });

    sock.ev.on('messages.upsert', async ({ messages, type, requestId }) => {
      // In self-chat mode, your own messages commonly arrive as 'append' rather
      // than 'notify'. Accept both and filter agent echo-backs below.
      if (type !== 'notify' && type !== 'append') return;
      if (generation !== socketGeneration) return;

      // requestId on the *event* means the phone resent messages while we were
      // offline — those are legitimate and must be processed (especially after
      // 408/428 reconnects). GHSA-qvv5-jq5g-4cgg is patched in Baileys 6.7.23.
      if (requestId && WHATSAPP_DEBUG) {
        try {
          console.log(JSON.stringify({
            event: 'upsert_from_phone_catchup',
            requestId,
            count: messages?.length || 0,
          }));
        } catch {}
      }

      const botIds = Array.from(new Set([
        normalizeWhatsAppId(sock?.user?.id),
        normalizeWhatsAppId(sock?.user?.lid),
      ].filter(Boolean)));

      for (const msg of messages) {
        if (!msg.message) continue;

      const chatId = msg.key.remoteJid;
      if (WHATSAPP_DEBUG) {
        try {
          console.log(JSON.stringify({
            event: 'upsert', type,
            fromMe: !!msg.key.fromMe, chatId,
            senderId: msg.key.participant || chatId,
            messageKeys: Object.keys(msg.message || {}),
          }));
        } catch {}
      }
      const senderId = msg.key.participant || chatId;
      const isGroup = chatId.endsWith('@g.us');
      const senderNumber = senderId.replace(/@.*/, '');

      // Handle fromMe messages based on mode
      if (msg.key.fromMe) {
        if (isGroup || chatId.includes('status')) continue;

        if (WHATSAPP_MODE === 'bot') {
          // Bot mode: separate number. ALL fromMe are echo-backs of our own replies — skip.
          continue;
        }

        // Self-chat mode: only allow messages in the user's own self-chat
        // WhatsApp now uses LID (Linked Identity Device) format: 67427329167522@lid
        // AND classic format: 34652029134@s.whatsapp.net
        // sock.user has both: { id: "number:10@s.whatsapp.net", lid: "lid_number:10@lid" }
        const myNumber = (sock.user?.id || '').replace(/:.*@/, '@').replace(/@.*/, '');
        const myLid = (sock.user?.lid || '').replace(/:.*@/, '@').replace(/@.*/, '');
        const chatNumber = chatId.replace(/@.*/, '');
        const isSelfChat = (myNumber && chatNumber === myNumber) || (myLid && chatNumber === myLid);
        if (!isSelfChat) continue;
      }

      // Handle !fromMe messages (from other people) based on mode.
      // Self-chat mode only responds to the user's own messages to
      // themselves — stranger DMs / group pings must never reach the
      // Python gateway, otherwise a pairing-code reply fires in response
      // to arbitrary incoming messages (#8389).
      if (!msg.key.fromMe) {
        if (WHATSAPP_MODE === 'self-chat') {
          try {
            console.log(JSON.stringify({
              event: 'ignored',
              reason: 'self_chat_mode_rejects_non_self',
              chatId,
              senderId,
            }));
          } catch {}
          continue;
        }
        if (!matchesAllowedUser(senderId, ALLOWED_USERS, SESSION_DIR)) {
          try {
            console.log(JSON.stringify({
              event: 'ignored',
              reason: 'allowlist_mismatch',
              chatId,
              senderId,
            }));
          } catch {}
          continue;
        }
      }

      const messageContent = getMessageContent(msg);
      const contextInfo = getContextInfo(messageContent);
      const mentionedIds = Array.from(new Set((contextInfo?.mentionedJid || []).map(normalizeWhatsAppId).filter(Boolean)));
      const quotedMessageId = contextInfo?.stanzaId || null;
      const quotedParticipant = normalizeWhatsAppId(contextInfo?.participant || '') || null;
      const quotedRemoteJid = normalizeWhatsAppId(contextInfo?.remoteJid || '') || null;
      const hasQuotedMessage = !!contextInfo?.quotedMessage;

      // Extract message body
      let body = '';
      let hasMedia = false;
      let mediaType = '';
      const mediaUrls = [];

      if (messageContent.conversation) {
        body = messageContent.conversation;
      } else if (messageContent.extendedTextMessage?.text) {
        body = messageContent.extendedTextMessage.text;
      } else if (messageContent.imageMessage) {
        body = messageContent.imageMessage.caption || '';
        hasMedia = true;
        mediaType = 'image';
        try {
          const buf = await downloadMediaMessage(msg, 'buffer', {}, { logger, reuploadRequest: sock.updateMediaMessage });
          const mime = messageContent.imageMessage.mimetype || 'image/jpeg';
          const extMap = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp', 'image/gif': '.gif' };
          const ext = extMap[mime] || '.jpg';
          mkdirSync(IMAGE_CACHE_DIR, { recursive: true });
          const filePath = path.join(IMAGE_CACHE_DIR, `img_${randomBytes(6).toString('hex')}${ext}`);
          writeFileSync(filePath, buf);
          mediaUrls.push(filePath);
        } catch (err) {
          console.error('[bridge] Failed to download image:', err.message);
        }
      } else if (messageContent.videoMessage) {
        body = messageContent.videoMessage.caption || '';
        hasMedia = true;
        mediaType = 'video';
        try {
          const buf = await downloadMediaMessage(msg, 'buffer', {}, { logger, reuploadRequest: sock.updateMediaMessage });
          const mime = messageContent.videoMessage.mimetype || 'video/mp4';
          const ext = mime.includes('mp4') ? '.mp4' : '.mkv';
          mkdirSync(DOCUMENT_CACHE_DIR, { recursive: true });
          const filePath = path.join(DOCUMENT_CACHE_DIR, `vid_${randomBytes(6).toString('hex')}${ext}`);
          writeFileSync(filePath, buf);
          mediaUrls.push(filePath);
        } catch (err) {
          console.error('[bridge] Failed to download video:', err.message);
        }
      } else if (messageContent.audioMessage || messageContent.pttMessage) {
        hasMedia = true;
        mediaType = messageContent.pttMessage ? 'ptt' : 'audio';
        try {
          const audioMsg = messageContent.pttMessage || messageContent.audioMessage;
          const buf = await downloadMediaMessage(msg, 'buffer', {}, { logger, reuploadRequest: sock.updateMediaMessage });
          const mime = audioMsg.mimetype || 'audio/ogg';
          const ext = mime.includes('ogg') ? '.ogg' : mime.includes('mp4') ? '.m4a' : '.ogg';
          mkdirSync(AUDIO_CACHE_DIR, { recursive: true });
          const filePath = path.join(AUDIO_CACHE_DIR, `aud_${randomBytes(6).toString('hex')}${ext}`);
          writeFileSync(filePath, buf);
          mediaUrls.push(filePath);
        } catch (err) {
          console.error('[bridge] Failed to download audio:', err.message);
        }
      } else if (messageContent.documentMessage) {
        body = messageContent.documentMessage.caption || '';
        hasMedia = true;
        mediaType = 'document';
        const fileName = messageContent.documentMessage.fileName || 'document';
        try {
          const buf = await downloadMediaMessage(msg, 'buffer', {}, { logger, reuploadRequest: sock.updateMediaMessage });
          mkdirSync(DOCUMENT_CACHE_DIR, { recursive: true });
          const safeFileName = path.basename(fileName).replace(/[^a-zA-Z0-9._-]/g, '_');
          const filePath = path.join(DOCUMENT_CACHE_DIR, `doc_${randomBytes(6).toString('hex')}_${safeFileName}`);
          writeFileSync(filePath, buf);
          mediaUrls.push(filePath);
        } catch (err) {
          console.error('[bridge] Failed to download document:', err.message);
        }
      }

      // For media without caption, use a placeholder so the API message is never empty
      if (hasMedia && !body) {
        body = `[${mediaType} received]`;
      }

      // Ignore Centurion' own reply messages in self-chat mode to avoid loops.
      if (msg.key.fromMe && ((REPLY_PREFIX && body.startsWith(REPLY_PREFIX)) || recentlySentIds.has(msg.key.id))) {
        if (WHATSAPP_DEBUG) {
          try { console.log(JSON.stringify({ event: 'ignored', reason: 'agent_echo', chatId, messageId: msg.key.id })); } catch {}
        }
        continue;
      }

      // Skip empty messages
      if (!body && !hasMedia) {
        if (WHATSAPP_DEBUG) {
          try { 
            console.log(JSON.stringify({ event: 'ignored', reason: 'empty', chatId, messageKeys: Object.keys(msg.message || {}) })); 
          } catch (err) {
            console.error('Failed to log empty message event:', err);
          }
        }
        continue;
      }

      const event = {
        messageId: msg.key.id,
        chatId,
        senderId,
        senderName: msg.pushName || senderNumber,
        chatName: isGroup ? (chatId.split('@')[0]) : (msg.pushName || senderNumber),
        isGroup,
        body,
        hasMedia,
        mediaType,
        mediaUrls,
        mentionedIds,
        quotedMessageId,
        quotedParticipant,
        quotedRemoteJid,
        hasQuotedMessage,
        botIds,
        timestamp: msg.messageTimestamp,
      };

      messageQueue.push(event);
      if (messageQueue.length > MAX_QUEUE_SIZE) {
        messageQueue.shift();
      }
    }
  });
  } catch (err) {
    console.error('❌ Failed to start WhatsApp socket:', err?.message || err);
    startingSocket = false;
    scheduleReconnect(
      DisconnectReason.connectionLost,
      String(err?.message || err),
    );
  }
}

// HTTP server
const app = express();
app.use(express.json());

// Host-header validation — defends against DNS rebinding.
// The bridge binds loopback-only (127.0.0.1) but a victim browser on
// the same machine could be tricked into fetching from an attacker
// hostname that TTL-flips to 127.0.0.1. Reject any request whose Host
// header doesn't resolve to a loopback alias.
// See GHSA-ppp5-vxwm-4cf7.
const _ACCEPTED_HOST_VALUES = new Set([
  'localhost',
  '127.0.0.1',
  '[::1]',
  '::1',
]);

app.use((req, res, next) => {
  const raw = (req.headers.host || '').trim();
  if (!raw) {
    return res.status(400).json({ error: 'Missing Host header' });
  }
  // Strip port suffix: "localhost:3000" → "localhost"
  const hostOnly = (raw.includes(':')
    ? raw.substring(0, raw.lastIndexOf(':'))
    : raw
  ).replace(/^\[|\]$/g, '').toLowerCase();
  if (!_ACCEPTED_HOST_VALUES.has(hostOnly)) {
    return res.status(400).json({
      error: 'Invalid Host header. Bridge accepts loopback hosts only.',
    });
  }
  next();
});

// Poll for new messages (long-poll style)
app.get('/messages', (req, res) => {
  const msgs = messageQueue.splice(0, messageQueue.length);
  res.json(msgs);
});

// Send a message
app.post('/send', async (req, res) => {
  if (!sock || connectionState !== 'connected') {
    return res.status(503).json({ error: 'Not connected to WhatsApp' });
  }

  const { chatId, message, replyTo } = req.body;
  if (!chatId || !message) {
    return res.status(400).json({ error: 'chatId and message are required' });
  }

  try {
    const chunks = splitLongMessage(formatOutgoingMessage(message));
    const messageIds = [];
    for (let i = 0; i < chunks.length; i += 1) {
      const sent = await sendWithTimeout(chatId, { text: chunks[i] });
      trackSentMessageId(sent);
      if (sent?.key?.id) messageIds.push(sent.key.id);
      if (chunks.length > 1 && i < chunks.length - 1) {
        await sleep(CHUNK_DELAY_MS);
      }
    }

    res.json({
      success: true,
      messageId: messageIds[messageIds.length - 1],
      messageIds,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Edit a previously sent message
app.post('/edit', async (req, res) => {
  if (!sock || connectionState !== 'connected') {
    return res.status(503).json({ error: 'Not connected to WhatsApp' });
  }

  const { chatId, messageId, message } = req.body;
  if (!chatId || !messageId || !message) {
    return res.status(400).json({ error: 'chatId, messageId, and message are required' });
  }

  try {
    const key = { id: messageId, fromMe: true, remoteJid: chatId };
    const chunks = splitLongMessage(formatOutgoingMessage(message));
    const messageIds = [];

    await sendWithTimeout(chatId, { text: chunks[0], edit: key });
    if (chunks.length > 1) {
      for (let i = 1; i < chunks.length; i += 1) {
        const sent = await sendWithTimeout(chatId, { text: chunks[i] });
        trackSentMessageId(sent);
        if (sent?.key?.id) messageIds.push(sent.key.id);
        if (i < chunks.length - 1) {
          await sleep(CHUNK_DELAY_MS);
        }
      }
    }

    res.json({ success: true, messageIds });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// MIME type map and media type inference for /send-media
const MIME_MAP = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png',
  webp: 'image/webp', gif: 'image/gif',
  mp4: 'video/mp4', mov: 'video/quicktime', avi: 'video/x-msvideo',
  mkv: 'video/x-matroska', '3gp': 'video/3gpp',
  pdf: 'application/pdf',
  doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

function inferMediaType(ext) {
  if (['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(ext)) return 'image';
  if (['mp4', 'mov', 'avi', 'mkv', '3gp'].includes(ext)) return 'video';
  if (['ogg', 'opus', 'mp3', 'wav', 'm4a'].includes(ext)) return 'audio';
  return 'document';
}

// Send media (image, video, document) natively
app.post('/send-media', async (req, res) => {
  if (!sock || connectionState !== 'connected') {
    return res.status(503).json({ error: 'Not connected to WhatsApp' });
  }

  const { chatId, filePath, mediaType, caption, fileName } = req.body;
  if (!chatId || !filePath) {
    return res.status(400).json({ error: 'chatId and filePath are required' });
  }

  try {
    if (!existsSync(filePath)) {
      return res.status(404).json({ error: `File not found: ${filePath}` });
    }

    const buffer = readFileSync(filePath);
    const ext = filePath.toLowerCase().split('.').pop();
    const type = mediaType || inferMediaType(ext);
    let msgPayload;

    switch (type) {
      case 'image':
        msgPayload = { image: buffer, caption: caption || undefined, mimetype: MIME_MAP[ext] || 'image/jpeg' };
        break;
      case 'video':
        msgPayload = { video: buffer, caption: caption || undefined, mimetype: MIME_MAP[ext] || 'video/mp4' };
        break;
      case 'audio': {
        // WhatsApp only renders a native voice bubble (ptt) when the file is ogg/opus.
        // If the caller passes mp3, wav, m4a etc. (e.g. from Edge TTS / NeuTTS),
        // silently convert to ogg/opus via ffmpeg so ptt is always honoured.
        let audioBuffer = buffer;
        let audioExt = ext;
        const needsConversion = !['ogg', 'opus'].includes(ext);
        let tmpPath = null;
        if (needsConversion) {
          tmpPath = path.join(tmpdir(), `centurion_voice_${randomBytes(6).toString('hex')}.ogg`);
          try {
            execSync(
              `ffmpeg -y -i ${JSON.stringify(filePath)} -ar 48000 -ac 1 -c:a libopus ${JSON.stringify(tmpPath)}`,
              { timeout: 30000, stdio: 'pipe' }
            );
            audioBuffer = readFileSync(tmpPath);
            audioExt = 'ogg';
          } catch (convErr) {
            // ffmpeg not available or conversion failed — fall back to original format
            console.warn('[bridge] ffmpeg conversion failed, sending as file attachment:', convErr.message);
          } finally {
            try { if (tmpPath && existsSync(tmpPath)) unlinkSync(tmpPath); } catch (_) {}
          }
        }
        const audioMime = (audioExt === 'ogg' || audioExt === 'opus') ? 'audio/ogg; codecs=opus' : 'audio/mpeg';
        msgPayload = { audio: audioBuffer, mimetype: audioMime, ptt: audioExt === 'ogg' || audioExt === 'opus' };
        break;
      }
      case 'document':
      default:
        msgPayload = {
          document: buffer,
          fileName: fileName || path.basename(filePath),
          caption: caption || undefined,
          mimetype: MIME_MAP[ext] || 'application/octet-stream',
        };
        break;
    }

    const sent = await sendWithTimeout(chatId, msgPayload);

    trackSentMessageId(sent);

    res.json({ success: true, messageId: sent?.key?.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Typing indicator
app.post('/typing', async (req, res) => {
  if (!sock || connectionState !== 'connected') {
    return res.status(503).json({ error: 'Not connected' });
  }

  const { chatId } = req.body;
  if (!chatId) return res.status(400).json({ error: 'chatId required' });

  try {
    await sock.sendPresenceUpdate('composing', chatId);
    res.json({ success: true });
  } catch (err) {
    res.json({ success: false });
  }
});

// Chat info
app.get('/chat/:id', async (req, res) => {
  const chatId = req.params.id;
  const isGroup = chatId.endsWith('@g.us');

  if (isGroup && sock) {
    try {
      const metadata = await sock.groupMetadata(chatId);
      return res.json({
        name: metadata.subject,
        isGroup: true,
        participants: metadata.participants.map(p => p.id),
      });
    } catch {
      // Fall through to default
    }
  }

  res.json({
    name: chatId.replace(/@.*/, ''),
    isGroup,
    participants: [],
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: connectionState,
    queueLength: messageQueue.length,
    uptime: process.uptime(),
    reconnectAttempts,
    baileys: '@whiskeysockets/baileys@6.7.23',
  });
});

// Start
if (PAIR_ONLY) {
  // Pair-only mode: just connect, show QR, save creds, exit. No HTTP server.
  console.log('📱 WhatsApp pairing mode');
  console.log(`📁 Session: ${SESSION_DIR}`);
  console.log();
  startSocket();
} else {
  app.listen(PORT, '127.0.0.1', () => {
    console.log(`🌉 WhatsApp bridge listening on port ${PORT} (mode: ${WHATSAPP_MODE})`);
    console.log(`📁 Session stored in: ${SESSION_DIR}`);
    if (ALLOWED_USERS.size > 0) {
      console.log(`🔒 Allowed users: ${Array.from(ALLOWED_USERS).join(', ')}`);
    } else if (WHATSAPP_MODE === 'self-chat') {
      console.log(`🔒 Self-chat mode — only your own messages to yourself are processed.`);
    } else {
      console.log(`🔒 No WHATSAPP_ALLOWED_USERS set — incoming messages are rejected.`);
      console.log(`   Set WHATSAPP_ALLOWED_USERS=<phone> to authorize specific users,`);
      console.log(`   or WHATSAPP_ALLOWED_USERS=* for an explicit open bot.`);
    }
    console.log();
    startSocket();
  });
}
