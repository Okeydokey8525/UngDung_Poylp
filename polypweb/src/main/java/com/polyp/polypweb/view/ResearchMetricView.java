package com.polyp.polypweb.view;

public class ResearchMetricView {

    private final String label;
    private final String value;
    private final String description;

    public ResearchMetricView(String label, String value, String description) {
        this.label = label;
        this.value = value;
        this.description = description;
    }

    public String getLabel() {
        return label;
    }

    public String getValue() {
        return value;
    }

    public String getDescription() {
        return description;
    }
}
