package com.polyp.polypweb.view.export;

import java.time.LocalDateTime;

public record ComparisonMetadataExport(
        String comparisonGroupId,
        String fileName,
        LocalDateTime createdAt,
        ModelMetadataExport baseline,
        ModelMetadataExport vmamba) {
}
