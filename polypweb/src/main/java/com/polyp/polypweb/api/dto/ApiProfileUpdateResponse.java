package com.polyp.polypweb.api.dto;

public record ApiProfileUpdateResponse(
        ApiUserResponse user,
        boolean reauthenticationRequired
) {
}
