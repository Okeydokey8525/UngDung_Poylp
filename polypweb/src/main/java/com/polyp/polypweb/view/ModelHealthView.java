package com.polyp.polypweb.view;

public class ModelHealthView {

    private final String name;
    private final String family;
    private final String status;
    private final boolean ready;

    public ModelHealthView(String name, String family, String status, boolean ready) {
        this.name = name;
        this.family = family;
        this.status = status;
        this.ready = ready;
    }

    public String getName() {
        return name;
    }

    public String getFamily() {
        return family;
    }

    public String getStatus() {
        return status;
    }

    public boolean isReady() {
        return ready;
    }
}
