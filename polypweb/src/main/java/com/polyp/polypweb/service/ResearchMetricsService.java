package com.polyp.polypweb.service;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;
import tools.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.io.InputStream;
import java.util.List;
import java.util.Locale;

/**
 * Research results shown on /metrics. The numbers are not computed here: they are exported from the
 * verified thesis tables (CNTT_KLCN182_PhungTheBao/00_tai_lieu_tong_quan/bang/*.csv) by scripts/xuat_chi_so_web.py into
 * classpath:research/research-metrics.json, so every value on the page traces back to a CSV.
 */
@Service
public class ResearchMetricsService {

    static final String RESOURCE = "research/research-metrics.json";
    private static final Locale VI = Locale.forLanguageTag("vi-VN");
    private static final double ALPHA = 0.05;

    private final Report report;

    public ResearchMetricsService(ObjectMapper objectMapper) {
        this.report = load(objectMapper);
    }

    public Report report() {
        return report;
    }

    public boolean available() {
        return report != null;
    }

    private static Report load(ObjectMapper objectMapper) {
        ClassPathResource resource = new ClassPathResource(RESOURCE);
        if (!resource.exists()) {
            return null;
        }
        try (InputStream input = resource.getInputStream()) {
            return objectMapper.readValue(input, Report.class);
        } catch (IOException | RuntimeException exception) {
            return null;
        }
    }

    // ---- formatting helpers used by the template (decimal comma, as in the thesis report)

    public static String f(Double value, int digits) {
        return value == null ? "—" : String.format(VI, "%." + digits + "f", value);
    }

    public static String signed(Double value, int digits) {
        if (value == null) {
            return "—";
        }
        return (value >= 0 ? "+" : "−") + String.format(VI, "%." + digits + "f", Math.abs(value));
    }

    public static String meanSd(Double mean, Double sd) {
        return f(mean, 4) + " ± " + f(sd, 4);
    }

    public static String p(Double value) {
        if (value == null) {
            return "—";
        }
        return value < 0.001 ? "< 0,001" : f(value, 3);
    }

    public static boolean significant(Double pValue) {
        return pValue != null && pValue < ALPHA;
    }

    public static String millions(long value) {
        return String.format(VI, "%.2f triệu", value / 1_000_000.0);
    }

    public static String percent(Double value) {
        return value == null ? "—" : String.format(VI, "%.1f%%", value * 100);
    }

    /** Instance wrapper: Thymeleaf 3.1 blocks static calls (T(...)) in templates. */
    public static final class Formatter {
        public String f(Double value, int digits) {
            return ResearchMetricsService.f(value, digits);
        }

        public String signed(Double value, int digits) {
            return ResearchMetricsService.signed(value, digits);
        }

        public String meanSd(Double mean, Double sd) {
            return ResearchMetricsService.meanSd(mean, sd);
        }

        public String p(Double value) {
            return ResearchMetricsService.p(value);
        }

        public boolean significant(Double value) {
            return ResearchMetricsService.significant(value);
        }

        public String millions(long value) {
            return ResearchMetricsService.millions(value);
        }

        public String percent(Double value) {
            return ResearchMetricsService.percent(value);
        }

        public String modelLabel(String key) {
            return switch (key == null ? "" : key) {
                case "baseline" -> "YOLO26s-seg";
                case "tsvm" -> "YOLO26s-seg + C2TSVMamba";
                default -> key;
            };
        }
    }

    // ---- JSON shape (see xuat_chi_so_web.py)

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Report(
            String generatedOn,
            int seeds,
            Validation validation,
            Sources sources,
            List<PairedMetric> mask,
            List<PairedMetric> pixel,
            List<PixelReference> pixelReference,
            List<Cost> cost,
            List<EndToEnd> endToEnd) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Validation(int images, int polyp, int background) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Sources(String mask, String pixel, String cost, String endToEnd) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record PairedMetric(
            String metric,
            String label,
            Double baselineMean,
            Double baselineSd,
            Double tsvmMean,
            Double tsvmSd,
            Double delta,
            Double ci95Low,
            Double ci95High,
            Double pairedTP,
            Double wilcoxonP,
            int tsvmBetterSeeds) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record PixelReference(
            String model,
            String label,
            Double diceMean,
            Double diceSd,
            Double iouMean,
            Double iouSd,
            Double bgFpImageRate) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Cost(String model, long params, Double gflops, Double gpuMsMedian, Double gpuMsP95, String gpu) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record EndToEnd(
            String device,
            String model,
            int requests,
            Double clientMsMedian,
            Double clientMsP95,
            Double inferMsMedian,
            String date) {
    }
}
