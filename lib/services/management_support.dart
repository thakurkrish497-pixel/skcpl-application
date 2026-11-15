import 'package:supabase_flutter/supabase_flutter.dart';

bool isMissingManagementBackend(Object error) =>
    error is PostgrestException &&
    const ['PGRST202', 'PGRST204', 'PGRST205', '42883', '42P01']
        .contains(error.code);
