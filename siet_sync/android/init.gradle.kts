allprojects {
    tasks.withType(JavaCompile::class.java).configureEach {
        options.compilerArgs.addAll(listOf("-Xlint:-options"))
    }
}
