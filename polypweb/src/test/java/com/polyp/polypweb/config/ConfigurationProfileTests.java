package com.polyp.polypweb.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.ConfigDataApplicationContextInitializer;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class ConfigurationProfileTests {

    @Test
    void devProfileLoadsLocalSafeDefaultsAndTypedProperties() {
        profileRunner("dev").run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context.getEnvironment().getProperty("spring.mongodb.uri"))
                    .isEqualTo("mongodb://localhost:27017/polypweb");
            assertThat(context.getBean(AiServiceProperties.class).getBaseUrl().toString())
                    .isEqualTo("http://localhost:8000");
            assertThat(context.getBean(StorageProperties.class).getRoot().toString())
                    .isEqualTo("storage");
            assertThat(context.getEnvironment().getProperty(
                    "server.servlet.session.cookie.secure",
                    Boolean.class
            )).isFalse();
        });
    }

    @Test
    void prodProfileUsesEnvironmentValuesAndProductionCookieDefaults() {
        profileRunner("prod")
                .withPropertyValues(
                        "POLYPVISION_MONGODB_URI=mongodb://database:27017/polypweb",
                        "POLYPVISION_AI_BASE_URL=https://ai.internal",
                        "POLYPVISION_STORAGE_ROOT=runtime-storage"
                )
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context.getBean(AiServiceProperties.class).getBaseUrl().toString())
                            .isEqualTo("https://ai.internal");
                    assertThat(context.getEnvironment().getProperty(
                            "server.servlet.session.cookie.secure",
                            Boolean.class
                    )).isTrue();
                    assertThat(context.getEnvironment().getProperty(
                            "spring.devtools.restart.enabled",
                            Boolean.class
                    )).isFalse();
                    assertThat(context.getEnvironment().getProperty(
                            "app.security.hsts-enabled",
                            Boolean.class
                    )).isTrue();
                });
    }

    @Test
    void prodProfileHasNoLocalhostFallbackForRequiredDependencies() throws Exception {
        String properties = new ClassPathResource("application-prod.properties")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(properties)
                .contains("spring.mongodb.uri=${POLYPVISION_MONGODB_URI}")
                .contains("ai.api.base-url=${POLYPVISION_AI_BASE_URL}")
                .doesNotContain("mongodb://localhost")
                .doesNotContain("http://localhost");
    }

    @Test
    void prodProfileRejectsBlankRequiredAiConfiguration() {
        profileRunner("prod")
                .withPropertyValues(
                        "POLYPVISION_MONGODB_URI=",
                        "POLYPVISION_AI_BASE_URL="
                )
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void onlyHealthAndInfoAreExposed() throws Exception {
        String properties = new ClassPathResource("application.properties")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(properties)
                .contains("management.endpoints.web.exposure.include=health,info")
                .doesNotContain("management.endpoints.web.exposure.include=*");
    }

    private ApplicationContextRunner profileRunner(String profile) {
        return new ApplicationContextRunner()
                .withInitializer(new ConfigDataApplicationContextInitializer())
                .withPropertyValues("spring.profiles.active=" + profile)
                .withUserConfiguration(ProfileConfiguration.class);
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties({
            AiServiceProperties.class,
            StorageProperties.class
    })
    static class ProfileConfiguration {
    }
}
