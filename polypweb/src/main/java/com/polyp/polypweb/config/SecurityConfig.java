package com.polyp.polypweb.config;

import com.polyp.polypweb.api.security.ApiAuthenticationEntryPoint;
import com.polyp.polypweb.security.LoggingAccessDeniedHandler;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.authentication.session.ChangeSessionIdAuthenticationStrategy;
import org.springframework.security.web.authentication.session.SessionAuthenticationStrategy;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.security.web.header.writers.StaticHeadersWriter;
import org.springframework.security.web.util.matcher.AnyRequestMatcher;
import org.springframework.security.web.util.matcher.RequestMatcher;

@Configuration
public class SecurityConfig {

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public AuthenticationManager authenticationManager(
            AuthenticationConfiguration configuration) throws Exception {
        return configuration.getAuthenticationManager();
    }

    @Bean
    public SecurityContextRepository securityContextRepository() {
        return new HttpSessionSecurityContextRepository();
    }

    @Bean
    public SessionAuthenticationStrategy sessionAuthenticationStrategy() {
        return new ChangeSessionIdAuthenticationStrategy();
    }

    @Bean
    public SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            LoggingAccessDeniedHandler accessDeniedHandler,
            ApiAuthenticationEntryPoint apiAuthenticationEntryPoint,
            @Value("${app.security.hsts-enabled:false}") boolean hstsEnabled) throws Exception {
        RequestMatcher apiRequest = request -> {
            String contextPath = request.getContextPath();
            String prefix = (contextPath == null ? "" : contextPath) + "/api/v1/";
            return request.getRequestURI().startsWith(prefix);
        };
        String contentSecurityPolicy = "default-src 'self'; "
                + "base-uri 'self'; object-src 'none'; frame-ancestors 'none'; "
                + "img-src 'self' data:; "
                + "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
                + "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
                + "font-src 'self' data: https://cdn.jsdelivr.net; "
                + "connect-src 'self'; form-action 'self'";
        http
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers(HttpMethod.GET, "/api/v1/auth/csrf").permitAll()
                        .requestMatchers(
                                HttpMethod.POST,
                                "/api/v1/auth/register",
                                "/api/v1/auth/login"
                        ).permitAll()
                        .requestMatchers("/api/v1/**").authenticated()
                        .requestMatchers(
                                "/",
                                "/about",
                                "/login",
                                "/register",
                                "/css/**",
                                "/js/**",
                                "/images/**",
                                "/webjars/**",
                                "/error/**",
                                "/favicon.ico",
                                "/actuator/health",
                                "/actuator/info",
                                "/privacy",
                                "/terms",
                                "/disclaimer"
                        ).permitAll()
                        .requestMatchers("/admin/**").hasRole("ADMIN")
                        .requestMatchers(
                                "/diagnose/**",
                                "/compare/**",
                                "/history/**",
                                "/diagnoses/**",
                                "/comparisons/**",
                                "/dashboard",
                                "/profile/**",
                                "/media/**"
                        ).authenticated()
                        .anyRequest().authenticated()
                )
                .formLogin(form -> form
                        .loginPage("/login")
                        .loginProcessingUrl("/login")
                        .usernameParameter("email")
                        .passwordParameter("password")
                        .defaultSuccessUrl("/", false)
                        .failureUrl("/login?error")
                        .permitAll()
                )
                .logout(logout -> logout
                        .logoutUrl("/logout")
                        .logoutSuccessUrl("/login?logout")
                        .invalidateHttpSession(true)
                        .clearAuthentication(true)
                        .deleteCookies("JSESSIONID")
                        .permitAll()
                )
                .exceptionHandling(exception -> exception
                        .defaultAuthenticationEntryPointFor(
                                apiAuthenticationEntryPoint,
                                apiRequest
                        )
                        .defaultAuthenticationEntryPointFor(
                                new LoginUrlAuthenticationEntryPoint("/login"),
                                AnyRequestMatcher.INSTANCE
                        )
                        .accessDeniedHandler(accessDeniedHandler)
                )
                .headers(headers -> {
                    headers.addHeaderWriter(new StaticHeadersWriter(
                            "Referrer-Policy",
                            "strict-origin-when-cross-origin"
                    ));
                    headers.addHeaderWriter(new StaticHeadersWriter(
                            "Permissions-Policy",
                            "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
                    ));
                    headers.addHeaderWriter(new StaticHeadersWriter(
                            "Content-Security-Policy",
                            contentSecurityPolicy
                    ));
                    if (hstsEnabled) {
                        headers.httpStrictTransportSecurity(hsts -> hsts
                                .includeSubDomains(true)
                                .maxAgeInSeconds(31536000));
                    } else {
                        headers.httpStrictTransportSecurity(hsts -> hsts.disable());
                    }
                });

        return http.build();
    }
}
