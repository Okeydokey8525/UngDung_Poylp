package com.polyp.polypweb.api.dto;

public record ApiCsrfResponse(
        String token,
        String headerName,
        String parameterName
) {
}
