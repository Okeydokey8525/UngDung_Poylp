package com.polyp.polypweb;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class PolypwebApplication {

	public static void main(String[] args) {
		SpringApplication.run(PolypwebApplication.class, args);
	}

}
