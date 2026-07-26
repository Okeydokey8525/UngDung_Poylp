package com.polyp.polypweb.view;

public class ModelOptionView {

    private final String code;
    private final String name;
    private final String description;
    private final boolean vmamba;
    private final boolean enabled;

    public ModelOptionView(
            String code,
            String name,
            String description,
            boolean vmamba,
            boolean enabled) {
        this.code = code;
        this.name = name;
        this.description = description;
        this.vmamba = vmamba;
        this.enabled = enabled;
    }

    public String getCode() {
        return code;
    }

    public String getName() {
        return name;
    }

    public String getDescription() {
        return description;
    }

    public boolean isVmamba() {
        return vmamba;
    }

    public boolean isEnabled() {
        return enabled;
    }
}
