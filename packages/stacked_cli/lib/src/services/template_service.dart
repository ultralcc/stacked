import 'dart:async';
import 'dart:io';

import 'package:mustache_template/mustache_template.dart';
// TODO: Refactor into a service so we can mock out the return value
import 'package:path/path.dart' as p;
import 'package:pubspec_yaml/pubspec_yaml.dart';
import 'package:recase/recase.dart';
import 'package:stacked_cli/src/exceptions/invalid_stacked_structure_exception.dart';
import 'package:stacked_cli/src/locator.dart';
import 'package:stacked_cli/src/message_constants.dart';
// import 'package:stacked_cli/src/templates/generic_view_template.dart';
// import 'package:stacked_cli/src/templates/generic_viewmodel_template.dart';
// import 'package:stacked_cli/src/templates/generic_viewmodel_test_template.dart';
import 'package:stacked_cli/src/models/template_models.dart';
import 'package:stacked_cli/src/services/file_service.dart';
import 'package:stacked_cli/src/templates/template_constants.dart';
import 'package:stacked_cli/src/templates/template_helper.dart';

/// Given the data that points to templates it writes out those templates
/// using the same file paths
class TemplateService {
  final _fileService = locator<FileService>();
  final _templateHelper = locator<TemplateHelper>();

  /// Reads the template folder and creates the dart code that will be used to generate
  /// the templates
  Future<void> compileTemplateInformation() async {
    final templatesPath = _templateHelper.templatesPath;

    final stackedTemplateNames = await _fileService.getFoldersInDirectory(
      directoryPath: templatesPath,
    );

    final templateItemsToRender =
        await _templateHelper.getTemplateItemsToRender(
      templateNames: stackedTemplateNames,
    );

    final outputTemplate = Template(kTemplateDataStructure);
    final allTemplateItemsContent = outputTemplate.renderString({
      'templateItems': templateItemsToRender.map((e) => e.toJson()),
    });

    await _fileService.writeFile(
      file: File(p.join(templatesPath, 'compiled_templates.dart')),
      fileContent: allTemplateItemsContent,
    );

    // Creat the template map
  }

  /// Using the [templateName] this function will write out the template
  /// files in the directory the cli is currently running.
  Future<void> renderTemplate({
    required String templateName,

    /// The name to use for the views when generating the view template
    String? viewName,
    bool verbose = false,

    /// When set to true the newly generated view will not be added to the app.dart file
    bool excludeRoute = false,
  }) async {
    if (templateName == 'view') {
      if (viewName == null) {
        throw Exception(
            'When using the view template supplying the viewName parameter is required');
      }
    }

    // Get the template that we want to render
    final template = kCompiledStackedTemplates[templateName] ??
        StackedTemplate(templateFiles: []);

    await writeOutTemplateFiles(
      template: template,
      templateName: templateName,
      viewName: viewName,
    );

    if (templateName == 'view' && !excludeRoute) {
      await modifyExistingFiles(
        template: template,
        templateName: templateName,
        viewName: viewName,
      );
    }
  }

  Future<void> writeOutTemplateFiles({
    required StackedTemplate template,
    required String templateName,
    String? viewName,
  }) async {
    for (final templateFile in template.templateFiles) {
      final templateContent = renderContentForTemplate(
        content: templateFile.content,
        templateName: templateName,
        viewName: viewName,
      );

      final templateFileOutputPath = getTemplateOutputPath(
        inputTemplatePath: templateFile.relativeOutputPath,
        viewName: viewName,
      );

      await _fileService.writeFile(
        file: File(templateFileOutputPath),
        fileContent: templateContent,
      );
    }
  }

  /// Returns the output path for the file given the input path of the template
  String getTemplateOutputPath({
    required String inputTemplatePath,
    String? viewName,
  }) {
    // TODO: Remove the duplicate code
    final recaseViewName = ReCase(viewName ?? '');
    return inputTemplatePath.replaceAll(
      'generic',
      recaseViewName.snakeCase,
    );
  }

  /// Takes in a templated string [content] and builds the template data
  /// to use when rendering
  String renderContentForTemplate({
    required String content,
    required String templateName,
    String? viewName,
  }) {
    var viewTemplate = Template(content, lenient: true);

    // This functionality is separate and will have to move into its own place
    // It WILL become a lot more complicated.
    final viewNameRecase = ReCase(viewName ?? '');
    // TODO: Refactor this to get different render data depending on the template
    final renderData = {
      kTemplatePropertyViewName: '${viewNameRecase.pascalCase}View',
      kTemplatePropertyViewModelName: '${viewNameRecase.pascalCase}ViewModel',
      kTemplatePropertyViewModelFileName:
          '${viewNameRecase.snakeCase}_viewmodel.dart',
    };

    return viewTemplate.renderString(renderData);
  }

  Future<void> modifyExistingFiles({
    required StackedTemplate template,
    required String templateName,
    String? viewName,
  }) async {
    for (final fileToModify in template.modificationFiles) {
      final fileExists = await _fileService.fileExists(
        filePath: fileToModify.relativeModificationPath,
      );

      if (!fileExists) {
        throw InvalidStackedStructureException(kInvalidStackedStructureAppFile);
      }

      final fileContent = await _fileService.readFile(
        filePath: fileToModify.relativeModificationPath,
      );

      final updatedFileContent = templateModificationFileContent(
        fileContent: fileContent,
        modificationIdentifier: fileToModify.modificationIdentifier,
        modificationTemplate: fileToModify.modificationTemplate,
        viewName: viewName,
      );

      // Write the file back that was modified
      await _fileService.writeFile(
        file: File(fileToModify.relativeModificationPath),
        fileContent: updatedFileContent,
      );
    }
  }

  String templateModificationFileContent({
    required String fileContent,
    required String modificationTemplate,
    required String modificationIdentifier,
    String? viewName,
  }) {
    final template = Template(
      modificationTemplate,
      lenient: true,
    );

    // TODO: We need to be able to unit test this (will become important if it ever breaks somethings)
    final pubspecYaml = File('pubspec.yaml').readAsStringSync().toPubspecYaml();

    // TODO: Remove duplicate code below
    final viewNameRecase = ReCase(viewName ?? '');
    final renderedTemplate = template.renderString(
      {
        // TODO: Create helper extensions for modifying the viewName passed in
        kTemplatePropertyViewName: '${viewNameRecase.pascalCase}View',
        kTemplatePropertyPackageName: pubspecYaml.name,
        kTemplateViewFolderName: viewNameRecase.snakeCase,
        kTemplateViewFileName: '${viewNameRecase.snakeCase}_view.dart',
      },
    );

    // Take the content, replace the identifier in the file with the new code
    // plus the identifier so we can do the same thing again later.
    return fileContent.replaceFirst(
      modificationIdentifier,
      '$renderedTemplate\n$modificationIdentifier',
    );
  }
}