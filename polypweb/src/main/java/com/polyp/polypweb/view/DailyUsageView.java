package com.polyp.polypweb.view;

import java.time.LocalDate;

public class DailyUsageView {

    private final LocalDate date;
    private final String label;
    private final long count;
    private final double percentage;

    public DailyUsageView(LocalDate date, String label, long count, double percentage) {
        this.date = date;
        this.label = label;
        this.count = count;
        this.percentage = percentage;
    }

    public LocalDate getDate() {
        return date;
    }

    public String getLabel() {
        return label;
    }

    public long getCount() {
        return count;
    }

    public double getPercentage() {
        return percentage;
    }
}
