package com.proj16.backend.service;

import org.springframework.stereotype.Service;
import java.util.logging.Logger;

@Service
public class NotificationService {
    private static final Logger logger = Logger.getLogger(NotificationService.class.getName());

    /**
     * Sends a push notification to a specific user.
     * In a production environment, this would integrate with FCM or OneSignal.
     */
    public void sendPushNotification(String username, String title, String body) {
        logger.info("Sending Push Notification to [" + username + "]: " + title + " - " + body);
        
        // Mocking external API call to FCM/Appcenter
        simulateExternalNotificationService(username, title, body);
    }

    private void simulateExternalNotificationService(String user, String t, String b) {
        // Placeholder for real integration logic
        System.out.println("Notification dispatched via internal proxy for: " + user);
    }
}
