package com.polyp.polypweb.view;

import java.util.List;

public class AiHealthView {

    private final boolean reachable;
    private final String serviceStatus;
    private final String device;
    private final List<ModelHealthView> models;

    public AiHealthView(
            boolean reachable,
            String serviceStatus,
            String device,
            List<ModelHealthView> models) {
        this.reachable = reachable;
        this.serviceStatus = serviceStatus;
        this.device = device;
        this.models = List.copyOf(models);
    }

    public boolean isReachable() {
        return reachable;
    }

    public String getServiceStatus() {
        return serviceStatus;
    }

    public String getDevice() {
        return device;
    }

    public List<ModelHealthView> getModels() {
        return models;
    }
}
