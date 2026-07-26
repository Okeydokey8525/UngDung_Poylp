package com.polyp.polypweb.client;

public record AiServiceStatus(
        boolean baselineReady,
        boolean vmambaReady) {

    public boolean allModelsReady() {
        return baselineReady && vmambaReady;
    }
}
