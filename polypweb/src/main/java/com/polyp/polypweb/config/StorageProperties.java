package com.polyp.polypweb.config;

import jakarta.validation.constraints.NotNull;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.util.unit.DataSize;
import org.springframework.validation.annotation.Validated;

import java.nio.file.Path;

@Validated
@ConfigurationProperties(prefix = "app.storage")
public class StorageProperties {

    @NotNull
    private Path root;

    @NotNull
    private DataSize maxFileSize = DataSize.ofMegabytes(10);

    @NotNull
    private DataSize maxResultSize = DataSize.ofMegabytes(15);

    public Path getRoot() {
        return root;
    }

    public void setRoot(Path root) {
        if (root == null || root.toString().isBlank()) {
            throw new IllegalArgumentException("app.storage.root không được để trống.");
        }
        this.root = root;
    }

    public DataSize getMaxFileSize() {
        return maxFileSize;
    }

    public void setMaxFileSize(DataSize maxFileSize) {
        this.maxFileSize = requirePositive(maxFileSize, "max-file-size");
    }

    public DataSize getMaxResultSize() {
        return maxResultSize;
    }

    public void setMaxResultSize(DataSize maxResultSize) {
        this.maxResultSize = requirePositive(maxResultSize, "max-result-size");
    }

    private DataSize requirePositive(DataSize value, String name) {
        if (value == null || value.toBytes() <= 0) {
            throw new IllegalArgumentException("app.storage." + name + " phải lớn hơn 0.");
        }
        return value;
    }
}
