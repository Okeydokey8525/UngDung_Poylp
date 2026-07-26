package com.polyp.polypweb.controller;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.mock.web.MockHttpServletRequest;

import static org.junit.jupiter.api.Assertions.assertEquals;

class NavigationAdviceTests {

    private final NavigationAdvice advice = new NavigationAdvice();

    @ParameterizedTest
    @CsvSource({
            "'/', home",
            "/dashboard, dashboard",
            "/admin/dashboard, admin-dashboard",
            "/admin/users, admin-users",
            "/diagnose, diagnose",
            "/diagnoses/diagnosis-id, diagnose",
            "/compare, compare",
            "/comparisons, comparisons",
            "/comparisons/comparison-id, comparisons",
            "/history, history",
            "/about, about"
    })
    void resolvesActiveNavigationFromExactRoute(String path, String expectedActiveNav) {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", path);
        request.setRequestURI(path);

        assertEquals(expectedActiveNav, advice.activeNavigation(request));
    }
}
