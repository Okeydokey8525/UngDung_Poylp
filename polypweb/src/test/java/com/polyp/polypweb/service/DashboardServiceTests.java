package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.repository.DashboardStatisticsRepository;
import com.polyp.polypweb.repository.DashboardStatisticsSnapshot;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.UserAccountRepository;
import com.polyp.polypweb.view.AdminDashboardView;
import com.polyp.polypweb.view.AiHealthView;
import com.polyp.polypweb.view.ModelHealthView;
import com.polyp.polypweb.view.UserDashboardView;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DashboardServiceTests {

    private static final String USER_ID = "user-a";

    @Mock
    private DashboardStatisticsRepository statisticsRepository;
    @Mock
    private DiagnosisHistoryRepository historyRepository;
    @Mock
    private UserAccountRepository userAccountRepository;
    @Mock
    private AiInferenceClient aiInferenceClient;

    private DashboardService service;

    @BeforeEach
    void setUp() {
        service = new DashboardService(
                statisticsRepository,
                historyRepository,
                userAccountRepository,
                aiInferenceClient
        );
        lenient().when(historyRepository.findTop20ByUserIdOrderByCreatedAtDesc(any()))
                .thenReturn(List.of());
        lenient().when(historyRepository.findTop20ByOrderByCreatedAtDesc())
                .thenReturn(List.of());
        lenient().when(userAccountRepository.findTop5ByCreatedAtAfterOrderByCreatedAtDesc(any()))
                .thenReturn(List.of());
        lenient().when(aiInferenceClient.dashboardHealth()).thenReturn(readyHealth());
    }

    @Test
    void newUserReceivesSafeEmptyDashboard() {
        when(statisticsRepository.aggregate(USER_ID, 7))
                .thenReturn(DashboardStatisticsSnapshot.empty());

        UserDashboardView dashboard = service.userDashboard(USER_ID, "User A");

        assertTrue(dashboard.isEmpty());
        assertEquals(0, dashboard.getTotalInference());
        assertEquals(7, dashboard.getDailyUsage().size());
        assertTrue(dashboard.getRecentActivities().isEmpty());
    }

    @Test
    void userDashboardScopesAggregationAndRecentQueryToCurrentUser() {
        when(statisticsRepository.aggregate(USER_ID, 7)).thenReturn(statistics());

        service.userDashboard(USER_ID, "User A");

        verify(statisticsRepository).aggregate(USER_ID, 7);
        verify(historyRepository).findTop20ByUserIdOrderByCreatedAtDesc(USER_ID);
    }

    @Test
    void userKpisPreserveSingleComparisonAndInferenceDefinitions() {
        when(statisticsRepository.aggregate(USER_ID, 7)).thenReturn(statistics());

        UserDashboardView dashboard = service.userDashboard(USER_ID, "User A");

        assertEquals(3, dashboard.getSingleAnalysis());
        assertEquals(2, dashboard.getComparisonSessions());
        assertEquals(7, dashboard.getTotalInference());
    }

    @Test
    void detectedNotDetectedAndMaskTotalsAreMappedExactly() {
        when(statisticsRepository.aggregate(USER_ID, 7)).thenReturn(statistics());

        UserDashboardView dashboard = service.userDashboard(USER_ID, "User A");

        assertEquals(4, dashboard.getDetected());
        assertEquals(3, dashboard.getNotDetected());
        assertEquals(9, dashboard.getTotalMasks());
    }

    @Test
    void detectedConfidenceAndProcessingAverageAreNotRecalculatedFromOtherRows() {
        when(statisticsRepository.aggregate(USER_ID, 7)).thenReturn(statistics());

        UserDashboardView dashboard = service.userDashboard(USER_ID, "User A");

        assertEquals(82.5, dashboard.getAverageDetectedConfidence());
        assertEquals(148.5, dashboard.getAverageProcessingTimeMs());
    }

    @Test
    void modelUsageAndMostUsedModelAreMapped() {
        when(statisticsRepository.aggregate(USER_ID, 7)).thenReturn(statistics());

        UserDashboardView dashboard = service.userDashboard(USER_ID, "User A");

        assertEquals(4, dashboard.getBaselineUsage());
        assertEquals(3, dashboard.getVmambaUsage());
        assertEquals("YOLO26s-seg", dashboard.getMostUsedModel());
    }

    @Test
    void recentActivityIsLimitedToTenWithoutLoadingAllHistory() {
        when(statisticsRepository.aggregate(USER_ID, 7)).thenReturn(statistics());
        List<DiagnosisHistory> recent = new ArrayList<>();
        for (int index = 0; index < 20; index++) {
            recent.add(history("doc-" + index, USER_ID, null, false, "YOLO26s-seg"));
        }
        when(historyRepository.findTop20ByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(recent);

        UserDashboardView dashboard = service.userDashboard(USER_ID, "User A");

        assertEquals(10, dashboard.getRecentActivities().size());
    }

    @Test
    void comparisonResultsAreGroupedIntoOneRecentActivity() {
        when(statisticsRepository.aggregate(USER_ID, 7)).thenReturn(statistics());
        String groupId = UUID.randomUUID().toString();
        when(historyRepository.findTop20ByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(List.of(
                        history("baseline", USER_ID, groupId, true, "YOLO26s-seg"),
                        history("vmamba", USER_ID, groupId, true, "YOLO26s-TSVM-FP32-seg")
                ));

        UserDashboardView dashboard = service.userDashboard(USER_ID, "User A");

        assertEquals(1, dashboard.getRecentActivities().size());
        assertEquals(2, dashboard.getRecentActivities().get(0).getInferenceCount());
        assertEquals("Phiên so sánh", dashboard.getRecentActivities().get(0).getActivityType());
    }

    @Test
    void adminUserCountersComeFromRepositoryCounts() {
        prepareAdminCounts();
        when(statisticsRepository.aggregate(null, 7)).thenReturn(statistics());

        AdminDashboardView dashboard = service.adminDashboard();

        assertEquals(6, dashboard.getTotalUsers());
        assertEquals(5, dashboard.getEnabledUsers());
        assertEquals(1, dashboard.getDisabledUsers());
        assertEquals(5, dashboard.getUserRoleCount());
        assertEquals(1, dashboard.getAdminRoleCount());
    }

    @Test
    void adminHistoryAndComparisonTotalsComeFromSystemAggregation() {
        prepareAdminCounts();
        when(statisticsRepository.aggregate(null, 7)).thenReturn(statistics());

        AdminDashboardView dashboard = service.adminDashboard();

        assertEquals(7, dashboard.getTotalHistory());
        assertEquals(3, dashboard.getSingleAnalysis());
        assertEquals(2, dashboard.getComparisonSessions());
    }

    @Test
    void adminModelDetectionAndMaskKpisAreMapped() {
        prepareAdminCounts();
        when(statisticsRepository.aggregate(null, 7)).thenReturn(statistics());

        AdminDashboardView dashboard = service.adminDashboard();

        assertEquals(4, dashboard.getBaselineUsage());
        assertEquals(3, dashboard.getVmambaUsage());
        assertEquals(4, dashboard.getDetected());
        assertEquals(3, dashboard.getNotDetected());
        assertEquals(9, dashboard.getTotalMasks());
    }

    @Test
    void unavailableFastApiProducesFallbackInsteadOfDashboardFailure() {
        prepareAdminCounts();
        when(statisticsRepository.aggregate(null, 7)).thenReturn(statistics());
        when(aiInferenceClient.dashboardHealth()).thenThrow(new AiServiceException("offline"));

        AdminDashboardView dashboard = service.adminDashboard();

        assertFalse(dashboard.getAiHealth().isReachable());
        assertEquals(2, dashboard.getAiHealth().getModels().size());
        assertTrue(dashboard.getAiHealth().getModels().stream().noneMatch(ModelHealthView::isReady));
    }

    @Test
    void recentAdminActivitiesResolveUsersInOneBatch() {
        prepareAdminCounts();
        when(statisticsRepository.aggregate(null, 7)).thenReturn(statistics());
        DiagnosisHistory history = history("doc-a", USER_ID, null, false, "YOLO26s-seg");
        when(historyRepository.findTop20ByOrderByCreatedAtDesc()).thenReturn(List.of(history));
        UserAccount account = account(USER_ID, "User A", "a@example.com");
        when(userAccountRepository.findAllById(any())).thenReturn(List.of(account));

        AdminDashboardView dashboard = service.adminDashboard();

        assertEquals("User A", dashboard.getRecentActivities().get(0).getUserDisplay());
        verify(userAccountRepository).findAllById(any());
    }

    private DashboardStatisticsSnapshot statistics() {
        Map<LocalDate, Long> daily = new LinkedHashMap<>();
        daily.put(LocalDate.now(), 2L);
        return new DashboardStatisticsSnapshot(
                7,
                3,
                2,
                4,
                3,
                4,
                3,
                9,
                2,
                148.5,
                82.5,
                daily
        );
    }

    private void prepareAdminCounts() {
        when(userAccountRepository.count()).thenReturn(6L);
        when(userAccountRepository.countByEnabledTrue()).thenReturn(5L);
        when(userAccountRepository.countByEnabledFalse()).thenReturn(1L);
        when(userAccountRepository.countByRole(UserRole.USER)).thenReturn(5L);
        when(userAccountRepository.countByRole(UserRole.ADMIN)).thenReturn(1L);
    }

    private AiHealthView readyHealth() {
        return new AiHealthView(
                true,
                "Hoạt động",
                "cpu",
                List.of(
                        new ModelHealthView("YOLO26s-seg", "Baseline", "Sẵn sàng", true),
                        new ModelHealthView(
                                "YOLO26s-TSVM-FP32-seg",
                                "VMamba",
                                "Sẵn sàng",
                                true
                        )
                )
        );
    }

    private DiagnosisHistory history(
            String id,
            String userId,
            String groupId,
            boolean comparison,
            String model) {
        DiagnosisHistory history = new DiagnosisHistory(
                userId,
                "sample.jpg",
                model,
                true,
                "polyp",
                80,
                100,
                1,
                "/media/original/11111111-1111-1111-1111-111111111111.jpg",
                "/media/results/11111111-1111-1111-1111-111111111111_result.jpg",
                LocalDateTime.now(),
                groupId,
                comparison
        );
        history.setId(id);
        return history;
    }

    private UserAccount account(String id, String fullName, String email) {
        UserAccount account = new UserAccount();
        account.setId(id);
        account.setFullName(fullName);
        account.setEmail(email);
        account.setRole(UserRole.USER);
        account.setEnabled(true);
        account.setCreatedAt(LocalDateTime.now());
        return account;
    }
}
