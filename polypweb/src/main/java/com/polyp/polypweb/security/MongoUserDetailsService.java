package com.polyp.polypweb.security;

import com.polyp.polypweb.service.UserAccountService;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class MongoUserDetailsService implements UserDetailsService {

    private final UserAccountService userAccountService;

    public MongoUserDetailsService(UserAccountService userAccountService) {
        this.userAccountService = userAccountService;
    }

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        return userAccountService.findByEmail(username)
                .map(CurrentUserPrincipal::new)
                .orElseThrow(() -> new UsernameNotFoundException("Không thể xác thực tài khoản."));
    }
}
