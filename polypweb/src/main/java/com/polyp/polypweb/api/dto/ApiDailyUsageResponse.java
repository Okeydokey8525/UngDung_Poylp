package com.polyp.polypweb.api.dto;

import java.time.LocalDate;

public record ApiDailyUsageResponse(LocalDate date, long count) {
}
