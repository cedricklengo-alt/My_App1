allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// compileSdk/targetSdk de l'app : android/app/build.gradle.kts (37).
// Ici on force AUSSI les plugins (com.android.library) à compiler en 37,
// au moment où le plugin est appliqué (jamais en afterEvaluate).
subprojects {
    // :app garde son compileSdk=37 (app/build.gradle.kts) — ne JAMAIS le toucher
    // ici après évaluation ("too late to set compileSdk").
    if (project.name == "app") return@subprojects
    // Bibliothèques (plugins) : on force compileSdk=37 APRÈS leur propre bloc
    // android{} (certains plugins, ex. flutter_ringtone_player, mettent 33).
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)
            ?.apply { compileSdk = 37 }
    }
}