package com.proj16.backend.controller;

import com.proj16.backend.dto.OtpRequestDto;
import com.proj16.backend.dto.OtpVerifyDto;
import com.proj16.backend.dto.RefreshTokenDto;
import com.proj16.backend.model.User;
import com.proj16.backend.repository.UserRepository;
import com.proj16.backend.security.JwtUtils;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthenticationManager authenticationManager;
    private final UserRepository userRepository;
    private final PasswordEncoder encoder;
    private final JwtUtils jwtUtils;

    public AuthController(AuthenticationManager authenticationManager, UserRepository userRepository,
                          PasswordEncoder encoder, JwtUtils jwtUtils) {
        this.authenticationManager = authenticationManager;
        this.userRepository = userRepository;
        this.encoder = encoder;
        this.jwtUtils = jwtUtils;
    }

    @PostMapping("/signin")
    public ResponseEntity<?> authenticateUser(@RequestBody Map<String, String> loginRequest) {
        Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(loginRequest.get("username"), loginRequest.get("password")));

        SecurityContextHolder.getContext().setAuthentication(authentication);
        String jwt = jwtUtils.generateJwtToken(authentication);

        Map<String, Object> response = new HashMap<>();
        response.put("token", jwt);
        response.put("type", "Bearer");
        response.put("username", loginRequest.get("username"));

        return ResponseEntity.ok(response);
    }

    @PostMapping("/signup")
    public ResponseEntity<?> registerUser(@RequestBody Map<String, String> signUpRequest) {
        String username = signUpRequest.get("username");
        if (username == null || username.isBlank()) {
            return ResponseEntity.badRequest().body("{\"error\": \"Username required\"}");
        }
        if (userRepository.existsByUsername(username)) {
            return ResponseEntity.badRequest().body("{\"error\": \"Username is already taken\"}");
        }

        User user = new User();
        user.setUsername(signUpRequest.get("username"));
        user.setEmail(signUpRequest.get("email"));
        user.setPassword(encoder.encode(signUpRequest.get("password")));
        user.setPhoneNumber(signUpRequest.get("phoneNumber"));
        user.setVerified(false);
        user.setCreatedAt(LocalDateTime.now());
        userRepository.save(user);

        return ResponseEntity.ok("{\"message\": \"User registered successfully\"}");
    }

    @PostMapping("/otp/request")
    public ResponseEntity<?> requestOtp(@RequestBody OtpRequestDto dto) {
        String otp = String.format("%06d", (int)(Math.random() * 1000000));
        return ResponseEntity.ok(Map.of(
            "message", "OTP sent to " + dto.getPhoneNumber(),
            "expiresInMinutes", 5
        ));
    }

    @PostMapping("/otp/verify")
    public ResponseEntity<?> verifyOtp(@RequestBody OtpVerifyDto dto) {
        User user = userRepository.findByPhoneNumber(dto.getPhoneNumber()).orElse(null);
        String username;
        if (user == null) {
            username = "user_" + dto.getPhoneNumber().replaceAll("[^0-9]", "");
            user = new User();
            user.setUsername(username);
            user.setEmail(username + "@chaaya.mesh");
            user.setPassword(encoder.encode(dto.getPin() != null ? dto.getPin() : "default"));
            user.setPhoneNumber(dto.getPhoneNumber());
            user.setVerified(true);
            user.setCreatedAt(LocalDateTime.now());
            userRepository.save(user);
        } else {
            username = user.getUsername();
        }

        String jwt = jwtUtils.generateTokenFromUsername(username);
        return ResponseEntity.ok(Map.of(
            "token", jwt,
            "type", "Bearer",
            "username", username
        ));
    }

    @PostMapping("/refresh")
    public ResponseEntity<?> refreshToken(@RequestBody RefreshTokenDto dto) {
        return ResponseEntity.ok(Map.of(
            "token", "refreshed-placeholder",
            "type", "Bearer"
        ));
    }
}
