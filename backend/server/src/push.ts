import * as admin from 'firebase-admin';
import { config } from './config';
import { logger, createChildLogger } from './log';
import { getDb, query } from './db';

const log = createChildLogger({ module: 'push-notifications' });

let messaging: admin.messaging.Messaging | null = null;

export const initPushNotifications = (): void => {
  if (config.FIREBASE_PROJECT_ID && config.FIREBASE_CLIENT_EMAIL && config.FIREBASE_PRIVATE_KEY) {
    try {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: config.FIREBASE_PROJECT_ID,
          clientEmail: config.FIREBASE_CLIENT_EMAIL,
          privateKey: config.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        }),
      });
      messaging = admin.messaging();
      log.info('Firebase messaging initialized');
    } catch (e) {
      log.error('Failed to initialize Firebase', { error: (e as Error).message });
    }
  } else {
    log.warn('Firebase credentials not configured, push notifications disabled');
  }
};

export const sendPushNotification = async (
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<boolean> => {
  if (!messaging) {
    log.debug('Push notifications not available');
    return false;
  }

  try {
    const tokens = await getUserFCMTokens(userId);
    if (tokens.length === 0) {
      log.debug('No FCM tokens for user', { userId });
      return false;
    }

    const message = {
      tokens,
      notification: { title, body },
      data: data || {},
      android: {
        priority: 'high' as const,
        notification: { channelId: 'chhaya_messages', icon: 'ic_notification', color: '#4ADE80' },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1, 'content-available': 1 } },
      },
    };

    const response = await messaging.sendEachForMulticast(message);
    
    // Handle failed tokens
    if (response.failureCount > 0) {
      const failedTokens: string[] = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success && resp.error?.code === 'messaging/registration-token-not-registered') {
          failedTokens.push(tokens[idx]);
        }
      });
      if (failedTokens.length > 0) {
        await removeFCMTokens(userId, failedTokens);
      }
    }

    log.info('Push notification sent', { userId, success: response.successCount, failure: response.failureCount });
    return response.successCount > 0;
  } catch (e) {
    log.error('Push notification failed', { userId, error: (e as Error).message });
    return false;
  }
};

export const sendNewMessageNotification = async (
  userId: string,
  senderName: string,
  preview: string,
  conversationId: string,
  messageId: string
): Promise<void> => {
  await sendPushNotification(userId, senderName, preview, {
    type: 'new_message',
    conversationId,
    messageId,
  });
};

export const sendCallNotification = async (
  userId: string,
  callerName: string,
  callId: string,
  isVideo: boolean
): Promise<void> => {
  await sendPushNotification(userId, `${callerName} is calling`, isVideo ? 'Video call' : 'Voice call', {
    type: 'incoming_call',
    callId,
    isVideo: isVideo.toString(),
  });
};

export const registerFCMToken = async (userId: string, deviceId: string, token: string): Promise<void> => {
  await query(
    `INSERT INTO devices (user_id, id, fcm_token, last_active_at) 
     VALUES ($1, $2, $3, NOW()) 
     ON CONFLICT (id) DO UPDATE SET fcm_token = $3, last_active_at = NOW()`,
    [userId, deviceId, token]
  );
  log.info('FCM token registered', { userId, deviceId });
};

export const removeFCMToken = async (userId: string, deviceId: string): Promise<void> => {
  await query('UPDATE devices SET fcm_token = NULL WHERE user_id = $1 AND id = $2', [userId, deviceId]);
};

const getUserFCMTokens = async (userId: string): Promise<string[]> => {
  const result = await query<{ fcm_token: string }>(
    'SELECT fcm_token FROM devices WHERE user_id = $1 AND fcm_token IS NOT NULL',
    [userId]
  );
  return result.rows.map(r => r.fcm_token);
};

const removeFCMTokens = async (userId: string, tokens: string[]): Promise<void> => {
  await query(
    'UPDATE devices SET fcm_token = NULL WHERE user_id = $1 AND fcm_token = ANY($2)',
    [userId, tokens]
  );
  log.info('Removed invalid FCM tokens', { userId, count: tokens.length });
};

export const subscribeToPush = async (userId: string, subscription: PushSubscription): Promise<void> => {
  await query(
    `INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth) 
     VALUES ($1, $2, $3, $4) 
     ON CONFLICT (endpoint) DO UPDATE SET p256dh = $3, auth = $4`,
    [userId, subscription.endpoint, subscription.keys.p256dh, subscription.keys.auth]
  );
};

export const unsubscribeFromPush = async (userId: string, endpoint: string): Promise<void> => {
  await query('DELETE FROM push_subscriptions WHERE user_id = $1 AND endpoint = $2', [userId, endpoint]);
};

interface PushSubscription {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}